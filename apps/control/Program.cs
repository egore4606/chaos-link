using System.Diagnostics;
using System.Text;
using System.Text.Json;

Console.OutputEncoding = Encoding.UTF8;
Console.InputEncoding = Encoding.UTF8;
Console.Title = "Chaos Link — управление и логи";

var root = ReadArgument("--root") ?? Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", ".."));
var runtime = Path.Combine(root, "runtime");
var accessPath = Path.Combine(runtime, "access.json");
var stopScript = Path.Combine(root, "Stop-ChaosLink.ps1");
var controlScript = Path.Combine(root, "Control-ChaosLink.ps1");
var outputLock = new object();

Directory.CreateDirectory(runtime);
PrintBanner();
PrintAccess();
PrintHelp();

using var cancellation = new CancellationTokenSource();
var logTask = FollowLogsAsync(cancellation.Token);

while (true)
{
    WritePrompt();
    var command = Console.ReadLine()?.Trim().ToLowerInvariant();
    if (string.IsNullOrWhiteSpace(command)) continue;
    switch (command)
    {
        case "help" or "помощь" or "?": PrintHelp(); break;
        case "status" or "статус": await PrintStatusAsync(); break;
        case "info" or "доступ": PrintAccess(); break;
        case "folder" or "папка": Process.Start(new ProcessStartInfo("explorer.exe", root) { UseShellExecute = true }); break;
        case "clear" or "очистить": Console.Clear(); PrintBanner(); break;
        case "restart" or "перезапуск":
            WriteLine("Перезапускаю сервер и игровой агент. HTTPS-туннель останется прежним...", ConsoleColor.Yellow);
            await RunElevatedAsync(controlScript, "-Action", "restart");
            await PrintStatusAsync();
            break;
        case "stop" or "стоп" or "выключить":
            WriteLine("Полностью останавливаю Chaos Link...", ConsoleColor.Yellow);
            StartElevated(stopScript);
            await Task.Delay(750);
            cancellation.Cancel();
            return;
        case "exit" or "выход":
            WriteLine("Консоль закрыта. Сервер продолжает работать; для остановки используйте команду stop.", ConsoleColor.Yellow);
            cancellation.Cancel();
            await IgnoreCancellation(logTask);
            return;
        default: WriteLine($"Неизвестная команда: {command}. Введите help.", ConsoleColor.Red); break;
    }
}

string? ReadArgument(string name)
{
    for (var index = 0; index < args.Length - 1; index++)
        if (args[index].Equals(name, StringComparison.OrdinalIgnoreCase)) return args[index + 1];
    return null;
}

void PrintBanner()
{
    WriteLine("============================================================", ConsoleColor.DarkGray);
    WriteLine("  CHAOS LINK — СИСТЕМА ЗАПУЩЕНА", ConsoleColor.Green);
    WriteLine($"  Папка установки: {root}", ConsoleColor.Gray);
    WriteLine("============================================================", ConsoleColor.DarkGray);
}

void PrintHelp()
{
    WriteLine("Команды: status · info · restart · stop · folder · clear · help · exit", ConsoleColor.Cyan);
    WriteLine("Логи сервера, агента и туннеля появляются в этом окне автоматически.", ConsoleColor.DarkGray);
}

void PrintAccess()
{
    try
    {
        using var document = JsonDocument.Parse(File.ReadAllText(accessPath));
        var data = document.RootElement;
        WriteLine("Данные для подключения:", ConsoleColor.Cyan);
        WriteLine($"  Сайт: {ReadProperty(data, "PublicUrl", "ещё создаётся")}", ConsoleColor.White);
        WriteLine($"  Код комнаты: {ReadProperty(data, "RoomCode", "—")}", ConsoleColor.White);
        WriteLine($"  Пароль друзей: {ReadProperty(data, "ControllerToken", "—")}", ConsoleColor.White);
        WriteLine($"  Пароль администратора: {ReadProperty(data, "AdminToken", "—")}", ConsoleColor.Yellow);
    }
    catch (Exception exception) { WriteLine($"Не удалось прочитать данные доступа: {exception.Message}", ConsoleColor.Red); }
}

async Task PrintStatusAsync()
{
    try
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        using var response = await client.GetAsync("http://127.0.0.1:5075/api/health");
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var health = document.RootElement;
        var agent = health.TryGetProperty("agentConnected", out var connected) && connected.GetBoolean();
        var controllers = health.TryGetProperty("controllers", out var count) ? count.GetInt32() : 0;
        WriteLine($"Статус: сервер работает · агент {(agent ? "подключён" : "не подключён")} · пользователей: {controllers}", agent ? ConsoleColor.Green : ConsoleColor.Yellow);
    }
    catch { WriteLine("Статус: сервер не отвечает.", ConsoleColor.Red); }
}

async Task FollowLogsAsync(CancellationToken token)
{
    var logs = new Dictionary<string, string>
    {
        [Path.Combine(runtime, "server.out.log")] = "SERVER",
        [Path.Combine(runtime, "server.err.log")] = "SERVER!",
        [Path.Combine(runtime, "agent.out.log")] = "AGENT",
        [Path.Combine(runtime, "agent.err.log")] = "AGENT!",
        [Path.Combine(runtime, "tunnel.err.log")] = "TUNNEL"
    };
    var positions = logs.Keys.ToDictionary(path => path, path => File.Exists(path) ? new FileInfo(path).Length : 0L);
    while (!token.IsCancellationRequested)
    {
        foreach (var (path, label) in logs)
        {
            try
            {
                if (!File.Exists(path)) continue;
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                if (positions[path] > stream.Length) positions[path] = 0;
                stream.Seek(positions[path], SeekOrigin.Begin);
                using var reader = new StreamReader(stream, Encoding.UTF8, true, 4096, leaveOpen: true);
                while (await reader.ReadLineAsync(token) is { } line)
                    if (!string.IsNullOrWhiteSpace(line)) WriteLine($"[{label}] {line}", ConsoleColor.DarkGray);
                positions[path] = stream.Position;
            }
            catch (OperationCanceledException) { return; }
            catch { }
        }
        try { await Task.Delay(500, token); } catch (OperationCanceledException) { return; }
    }
}

ProcessStartInfo ElevatedStartInfo(string script, params string[] arguments)
{
    if (!File.Exists(script)) throw new FileNotFoundException("Управляющий скрипт не найден", script);
    var start = new ProcessStartInfo { FileName = "powershell.exe", UseShellExecute = true, Verb = "runas", WorkingDirectory = root };
    start.ArgumentList.Add("-NoProfile"); start.ArgumentList.Add("-ExecutionPolicy"); start.ArgumentList.Add("Bypass");
    start.ArgumentList.Add("-File"); start.ArgumentList.Add(script);
    foreach (var argument in arguments) start.ArgumentList.Add(argument);
    return start;
}

void StartElevated(string script, params string[] arguments) => Process.Start(ElevatedStartInfo(script, arguments));

async Task RunElevatedAsync(string script, params string[] arguments)
{
    using var process = Process.Start(ElevatedStartInfo(script, arguments)) ?? throw new InvalidOperationException("Не удалось запустить управляющий скрипт");
    await process.WaitForExitAsync();
}

void WritePrompt()
{
    lock (outputLock) { Console.ForegroundColor = ConsoleColor.Green; Console.Write("chaos-link> "); Console.ResetColor(); }
}

void WriteLine(string message, ConsoleColor color)
{
    lock (outputLock) { Console.ForegroundColor = color; Console.WriteLine(message); Console.ResetColor(); }
}

static string ReadProperty(JsonElement element, string name, string fallback) =>
    element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? fallback : fallback;

static async Task IgnoreCancellation(Task task) { try { await task; } catch (OperationCanceledException) { } }
