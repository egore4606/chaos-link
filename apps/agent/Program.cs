using System.Diagnostics;
using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

Console.OutputEncoding = Encoding.UTF8;
var config = AgentConfig.Load();
var runner = new AhkRunner(config);

Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    runner.CancelAll();
};

Console.WriteLine("Chaos Link Agent");
Console.WriteLine($"Комната: {config.RoomCode}. Сервер: {config.ServerUrl}");
Console.WriteLine("Ctrl+C — остановить агент и отпустить все клавиши.");

while (true)
{
    try
    {
        using var socket = new ClientWebSocket();
        var uri = BuildUri(config);
        await socket.ConnectAsync(uri, CancellationToken.None);
        await AgentSocket.SendAsync(socket, new { type = "auth", token = config.AgentToken });
        Console.WriteLine("Подключено к серверу.");
        await ReceiveLoopAsync(socket, runner);
    }
    catch (Exception exception)
    {
        Console.WriteLine($"Связь потеряна: {exception.Message}");
    }

    runner.CancelAll();
    await Task.Delay(3000);
}

static Uri BuildUri(AgentConfig config)
{
    var separator = config.ServerUrl.Contains('?') ? '&' : '?';
    return new Uri($"{config.ServerUrl}{separator}room={Uri.EscapeDataString(config.RoomCode)}&role=agent&name={Uri.EscapeDataString(config.AgentName)}");
}

static async Task ReceiveLoopAsync(ClientWebSocket socket, AhkRunner runner)
{
    var buffer = new byte[8192];
    while (socket.State == WebSocketState.Open)
    {
        using var stream = new MemoryStream();
        WebSocketReceiveResult result;
        do
        {
            result = await socket.ReceiveAsync(buffer, CancellationToken.None);
            if (result.MessageType == WebSocketMessageType.Close) return;
            stream.Write(buffer, 0, result.Count);
        } while (!result.EndOfMessage);

        using var document = JsonDocument.Parse(stream.ToArray());
        var root = document.RootElement;
        if (!root.TryGetProperty("type", out var typeProperty)) continue;
        var type = typeProperty.GetString();

        if (type == "cancelAll")
        {
            runner.CancelAll();
            continue;
        }
        if (type != "command") continue;

        var command = root.Deserialize<AgentCommand>(JsonOptions.Default);
        if (command is null) continue;

        var delay = command.ExecuteAt - DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        if (delay > 0) await Task.Delay(TimeSpan.FromMilliseconds(delay));

        _ = ExecuteAndAckAsync(socket, runner, command);
    }
}

static async Task ExecuteAndAckAsync(ClientWebSocket socket, AhkRunner runner, AgentCommand command)
{
    var (status, detail) = await runner.ExecuteAsync(command);
    Console.WriteLine($"{DateTime.Now:HH:mm:ss} {command.EffectId}: {status} — {detail}");
    if (socket.State == WebSocketState.Open)
        await AgentSocket.SendAsync(socket, new { type = "ack", command.EventId, status, detail });
}

sealed class AhkRunner : IDisposable
{
    private static readonly HashSet<string> AllowedEffects =
    [
        "knife", "reload", "jump", "drop_weapon", "mouse_jerk",
        "hold_ctrl", "block_wasd", "block_lmb", "grenade_feet", "flash", "screamer"
    ];

    private readonly AgentConfig _config;
    private readonly ConcurrentDictionary<int, Process> _active = new();

    public AhkRunner(AgentConfig config) => _config = config;

    public async Task<(string Status, string Detail)> ExecuteAsync(AgentCommand command)
    {
        if (!AllowedEffects.Contains(command.EffectId))
            return ("rejected", "Эффект отсутствует в локальном белом списке");

        try
        {
            var scriptPath = ResolveScriptPath();
            var startInfo = new ProcessStartInfo
            {
                FileName = ResolveAutoHotkeyPath(),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            startInfo.ArgumentList.Add(scriptPath);
            startInfo.ArgumentList.Add("--effect");
            startInfo.ArgumentList.Add(command.EffectId);
            startInfo.ArgumentList.Add("--duration");
            startInfo.ArgumentList.Add(command.DurationMs.ToString());
            startInfo.ArgumentList.Add("--seed");
            startInfo.ArgumentList.Add(command.Seed.ToString());
            if (command.EffectId == "screamer")
            {
                var (imagePath, soundPath) = ChooseScreamerMedia();
                startInfo.ArgumentList.Add("--sound");
                startInfo.ArgumentList.Add(soundPath ?? "");
                startInfo.ArgumentList.Add("--image");
                startInfo.ArgumentList.Add(imagePath ?? "");
            }
            using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Не удалось запустить AutoHotkey");
            _active[process.Id] = process;
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            _active.TryRemove(process.Id, out _);
            var output = (await outputTask).Trim();
            var error = (await errorTask).Trim();
            return process.ExitCode == 0
                ? ("executed", string.IsNullOrWhiteSpace(output) ? "Выполнено AutoHotkey" : output)
                : ("failed", string.IsNullOrWhiteSpace(error) ? $"AutoHotkey завершился с кодом {process.ExitCode}" : error);
        }
        catch (Exception exception)
        {
            return ("failed", exception.Message);
        }
    }

    public void CancelAll()
    {
        foreach (var process in _active.Values)
        {
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
            }
            catch { }
        }
        _active.Clear();
        try
        {
            var cleanup = Process.Start(new ProcessStartInfo
            {
                FileName = ResolveAutoHotkeyPath(),
                Arguments = $"\"{ResolveScriptPath()}\" --effect release_all --duration 0 --seed 0",
                UseShellExecute = false,
                CreateNoWindow = true
            });
            cleanup?.WaitForExit(2000);
            cleanup?.Dispose();
        }
        catch { }
    }

    private string ResolveScriptPath()
    {
        var fromWorkingDirectory = Path.GetFullPath(_config.EffectsScript, Environment.CurrentDirectory);
        if (File.Exists(fromWorkingDirectory)) return fromWorkingDirectory;
        var fromBinaryDirectory = Path.GetFullPath(_config.EffectsScript, AppContext.BaseDirectory);
        if (File.Exists(fromBinaryDirectory)) return fromBinaryDirectory;
        throw new FileNotFoundException("AHK-скрипт не найден", fromWorkingDirectory);
    }

    private static string ResolveOptionalPath(string configuredPath)
    {
        if (Path.IsPathRooted(configuredPath)) return configuredPath;
        var fromWorkingDirectory = Path.GetFullPath(configuredPath, Environment.CurrentDirectory);
        if (File.Exists(fromWorkingDirectory)) return fromWorkingDirectory;
        var fromBinaryDirectory = Path.GetFullPath(configuredPath, AppContext.BaseDirectory);
        return File.Exists(fromBinaryDirectory) ? fromBinaryDirectory : fromWorkingDirectory;
    }

    private static string? ChooseRandomFile(string configuredDirectory, string[] allowedExtensions)
    {
        var directory = ResolveOptionalPath(configuredDirectory);
        if (!Directory.Exists(directory)) return null;
        var files = Directory.EnumerateFiles(directory)
            .Where(file => allowedExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase))
            .ToArray();
        return files.Length == 0 ? null : files[Random.Shared.Next(files.Length)];
    }

    private (string? ImagePath, string? SoundPath) ChooseScreamerMedia()
    {
        string[] imageExtensions = [".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".ico"];
        string[] soundExtensions = [".wav", ".mp3", ".wma", ".m4a", ".aac"];
        var imageDirectory = ResolveOptionalPath(_config.ScreamerImagesPath);
        var soundDirectory = ResolveOptionalPath(_config.ScreamerSoundsPath);

        var images = Directory.Exists(imageDirectory)
            ? Directory.EnumerateFiles(imageDirectory)
                .Where(file => imageExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase))
                .ToArray()
            : [];
        var sounds = Directory.Exists(soundDirectory)
            ? Directory.EnumerateFiles(soundDirectory)
                .Where(file => soundExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase))
                .ToArray()
            : [];

        var imagePath = images.Length == 0 ? null : images[Random.Shared.Next(images.Length)];
        if (imagePath is null)
            return (null, sounds.Length == 0 ? null : sounds[Random.Shared.Next(sounds.Length)]);

        var imageName = Path.GetFileNameWithoutExtension(imagePath);
        var matchingSounds = sounds
            .Where(sound => Path.GetFileNameWithoutExtension(sound).Equals(imageName, StringComparison.OrdinalIgnoreCase))
            .ToArray();
        var soundPool = matchingSounds.Length > 0 ? matchingSounds : sounds;
        var soundPath = soundPool.Length == 0 ? null : soundPool[Random.Shared.Next(soundPool.Length)];
        return (imagePath, soundPath);
    }

    private string ResolveAutoHotkeyPath()
    {
        if (Path.IsPathRooted(_config.AutoHotkeyPath) && File.Exists(_config.AutoHotkeyPath))
            return _config.AutoHotkeyPath;

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = new[]
        {
            Path.Combine(programFiles, "AutoHotkey", "v2", "AutoHotkey64.exe"),
            Path.Combine(programFiles, "AutoHotkey", "AutoHotkey.exe"),
            Path.Combine(localAppData, "Programs", "AutoHotkey", "v2", "AutoHotkey64.exe"),
            Path.Combine(localAppData, "Programs", "AutoHotkey", "AutoHotkey.exe")
        };
        return candidates.FirstOrDefault(File.Exists) ?? _config.AutoHotkeyPath;
    }

    public void Dispose()
    {
        CancelAll();
    }
}

sealed record AgentCommand(string Type, string EventId, string EffectId, int DurationMs, int Seed, long ExecuteAt);

sealed class AgentConfig
{
    public string ServerUrl { get; init; } = "ws://localhost:5075/ws";
    public string RoomCode { get; init; } = "K7M2";
    public string AgentName { get; init; } = "Игровой ПК";
    public string AgentToken { get; init; } = "agent-secret";
    public string AutoHotkeyPath { get; init; } = "AutoHotkey.exe";
    public string EffectsScript { get; init; } = "../../ahk/Effects.ahk";
    public string ScreamerSoundsPath { get; init; } = "../../screamer/sounds";
    public string ScreamerImagesPath { get; init; } = "../../screamer/images";

    public static AgentConfig Load()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        return File.Exists(path)
            ? JsonSerializer.Deserialize<AgentConfig>(File.ReadAllText(path), JsonOptions.Default) ?? new AgentConfig()
            : new AgentConfig();
    }
}

static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new(JsonSerializerDefaults.Web);
}

static class AgentSocket
{
    private static readonly SemaphoreSlim SendLock = new(1, 1);

    public static async Task SendAsync(ClientWebSocket socket, object payload)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(payload, JsonOptions.Default);
        await SendLock.WaitAsync();
        try
        {
            if (socket.State == WebSocketState.Open)
                await socket.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
        }
        finally { SendLock.Release(); }
    }
}
