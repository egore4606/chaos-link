using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
});
builder.Services.AddSingleton<RoomCoordinator>();

var app = builder.Build();
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(20) });

app.MapGet("/api/health", (RoomCoordinator rooms) => Results.Ok(new
{
    status = "ok",
    room = rooms.RoomCode,
    agentConnected = rooms.AgentConnected,
    controllers = rooms.ControllerCount,
    serverTime = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
}));

app.Map("/ws", async (HttpContext context, RoomCoordinator rooms) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    var room = context.Request.Query["room"].ToString().Trim().ToUpperInvariant();
    var role = context.Request.Query["role"].ToString().Trim().ToLowerInvariant();
    var name = context.Request.Query["name"].ToString().Trim();
    if (string.IsNullOrWhiteSpace(name)) name = role == "agent" ? "Игровой ПК" : "Друг";
    name = name[..Math.Min(name.Length, 24)];

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    using var authTimeout = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
    authTimeout.CancelAfter(TimeSpan.FromSeconds(5));
    ClientMessage? authMessage = null;
    try
    {
        var authJson = await ReceiveTextAsync(socket, authTimeout.Token);
        authMessage = JsonSerializer.Deserialize<ClientMessage>(authJson, new JsonSerializerOptions(JsonSerializerDefaults.Web));
    }
    catch (Exception exception) when (exception is JsonException or OperationCanceledException or WebSocketException)
    {
        await socket.CloseAsync(WebSocketCloseStatus.PolicyViolation, "Authentication required", CancellationToken.None);
        return;
    }

    if (authMessage?.Type != "auth" || !rooms.CanConnect(room, role, authMessage.Token ?? ""))
    {
        app.Logger.LogWarning("WebSocket authentication rejected: room={Room}, role={Role}, name={Name}", room, role, name);
        await socket.CloseAsync(WebSocketCloseStatus.PolicyViolation, "Invalid credentials", CancellationToken.None);
        return;
    }

    var connection = await rooms.AddAsync(socket, role, name, context.RequestAborted);

    try
    {
        var buffer = new byte[8192];
        while (socket.State == WebSocketState.Open && !context.RequestAborted.IsCancellationRequested)
        {
            var result = await socket.ReceiveAsync(buffer, context.RequestAborted);
            if (result.MessageType == WebSocketMessageType.Close) break;
            if (result.MessageType != WebSocketMessageType.Text) continue;

            using var stream = new MemoryStream();
            stream.Write(buffer, 0, result.Count);
            while (!result.EndOfMessage)
            {
                result = await socket.ReceiveAsync(buffer, context.RequestAborted);
                stream.Write(buffer, 0, result.Count);
            }

            var json = Encoding.UTF8.GetString(stream.ToArray());
            await rooms.HandleAsync(connection, json, context.RequestAborted);
        }
    }
    catch (OperationCanceledException) { }
    catch (WebSocketException) { }
    finally
    {
        await rooms.RemoveAsync(connection);
    }
});

app.MapFallbackToFile("index.html");
app.Run();

static async Task<string> ReceiveTextAsync(WebSocket socket, CancellationToken ct)
{
    var buffer = new byte[4096];
    using var stream = new MemoryStream();
    WebSocketReceiveResult result;
    do
    {
        result = await socket.ReceiveAsync(buffer, ct);
        if (result.MessageType != WebSocketMessageType.Text)
            throw new WebSocketException("Expected a text message");
        stream.Write(buffer, 0, result.Count);
    } while (!result.EndOfMessage);
    return Encoding.UTF8.GetString(stream.ToArray());
}

sealed class RoomCoordinator(IConfiguration configuration, ILogger<RoomCoordinator> logger)
{
    private readonly object _gate = new();
    private readonly ConcurrentDictionary<string, ClientConnection> _clients = new();
    private readonly Dictionary<string, long> _cooldowns = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, int> _cooldownOverrides = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, long> _activeUntil = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, long> _blockedUsersUntil = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<RoomEvent> _events = [];
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private bool _paused;

    public string RoomCode { get; } = configuration["ChaosLink:RoomCode"]?.ToUpperInvariant() ?? "K7M2";
    public bool AgentConnected => _clients.Values.Any(client => client.Role == "agent" && client.Socket.State == WebSocketState.Open);
    public int ControllerCount => _clients.Values.Count(client => client.Role is "controller" or "admin" && client.Socket.State == WebSocketState.Open);
    private string ControllerToken { get; } = configuration["ChaosLink:ControllerToken"] ?? "friend-access";
    private string AdminToken { get; } = configuration["ChaosLink:AdminToken"] ?? "admin-access";
    private string AgentToken { get; } = configuration["ChaosLink:AgentToken"] ?? "agent-secret";
    private int ExecutionLeadMs { get; } = configuration.GetValue("ChaosLink:ExecutionLeadMs", 250);

    private static readonly EffectDefinition[] Effects =
    [
        new("knife", "Достать нож", "Быстрые действия", "knife", 30, 0),
        new("reload", "Перезарядка", "Быстрые действия", "rotate-ccw", 30, 0),
        new("jump", "Прыжок", "Быстрые действия", "arrow-up", 30, 0),
        new("drop_weapon", "Выбросить оружие", "Быстрые действия", "trash-2", 45, 0),
        new("mouse_jerk", "Срыв сенсора", "Управление", "crosshair", 45, 7),
        new("hold_ctrl", "Удерживать Ctrl", "Управление", "square-chevron-down", 60, 10),
        new("block_wasd", "Заблокировать WASD", "Управление", "keyboard", 75, 10),
        new("block_lmb", "Заблокировать ЛКМ", "Управление", "mouse-pointer-2", 75, 10),
        new("grenade_feet", "Граната под себя", "Управление", "bomb", 90, 2),
        new("flash", "Белая флешка", "Экран и звук", "sun", 45, 3),
        new("screamer", "Скример", "Экран и звук", "volume-2", 90, 3)
    ];

    public bool CanConnect(string room, string role, string token) =>
        room == RoomCode && (role == "controller" && token == ControllerToken || role == "admin" && token == AdminToken || role == "agent" && token == AgentToken);

    public async Task<ClientConnection> AddAsync(WebSocket socket, string role, string name, CancellationToken ct)
    {
        var connection = new ClientConnection(Guid.NewGuid().ToString("N"), role, name, socket);
        _clients[connection.Id] = connection;
        logger.LogInformation("WebSocket connected: role={Role}, name={Name}, id={ClientId}", role, name, connection.Id);
        await SendAsync(connection, Snapshot(), ct);
        await BroadcastSnapshotAsync(ct);
        return connection;
    }

    public async Task RemoveAsync(ClientConnection connection)
    {
        _clients.TryRemove(connection.Id, out _);
        logger.LogInformation("WebSocket disconnected: role={Role}, name={Name}, id={ClientId}", connection.Role, connection.Name, connection.Id);
        await BroadcastSnapshotAsync(CancellationToken.None);
    }

    public async Task HandleAsync(ClientConnection connection, string json, CancellationToken ct)
    {
        ClientMessage? message;
        try { message = JsonSerializer.Deserialize<ClientMessage>(json, _json); }
        catch (JsonException)
        {
            await SendAsync(connection, new { type = "error", code = "invalid_json", message = "Некорректное сообщение" }, ct);
            return;
        }

        switch (message?.Type)
        {
            case "trigger" when connection.Role is "controller" or "admin" && message.EffectId is not null:
                await TriggerAsync(connection, message.EffectId, ct);
                break;
            case "pause" when connection.Role == "admin" && message.Paused.HasValue:
                await SetPausedAsync(connection, message.Paused.Value, ct);
                break;
            case "pause" when connection.Role == "controller":
                await SendAsync(connection, new { type = "error", code = "admin_required", message = "Паузой управляет только администратор" }, ct);
                break;
            case "blockUser" when connection.Role == "admin" && message.TargetClientId is not null:
                await BlockUserAsync(connection, message.TargetClientId, message.BlockSeconds ?? 30, ct);
                break;
            case "setCooldown" when connection.Role == "admin" && message.EffectId is not null && message.CooldownSeconds.HasValue:
                await SetCooldownAsync(connection, message.EffectId, message.CooldownSeconds.Value, ct);
                break;
            case "ack" when connection.Role == "agent" && message.EventId is not null:
                await AckAsync(message.EventId, message.Status ?? "executed", message.Detail, ct);
                break;
            case "ping":
                await SendAsync(connection, new { type = "pong", clientTime = message.ClientTime, serverTime = Now() }, ct);
                break;
            default:
                await SendAsync(connection, new { type = "error", code = "unsupported_message", message = "Команда не поддерживается" }, ct);
                break;
        }
    }

    private async Task TriggerAsync(ClientConnection controller, string effectId, CancellationToken ct)
    {
        var effect = Effects.FirstOrDefault(item => item.Id.Equals(effectId, StringComparison.OrdinalIgnoreCase));
        if (effect is null)
        {
            await RejectAsync(controller, effectId, "unknown_effect", "Неизвестный эффект", ct);
            return;
        }

        EffectCommand? command = null;
        string? rejectCode = null;
        string? rejectMessage = null;

        lock (_gate)
        {
            var now = Now();
            if (_paused)
            {
                rejectCode = "paused";
                rejectMessage = "Система на паузе";
            }
            else if (controller.Role == "controller" && _blockedUsersUntil.GetValueOrDefault(controller.Name) > now)
            {
                rejectCode = "user_blocked";
                rejectMessage = "Администратор заблокировал ваши команды";
            }
            else if (!_clients.Values.Any(client => client.Role == "agent" && client.Socket.State == WebSocketState.Open))
            {
                rejectCode = "agent_offline";
                rejectMessage = "Игровой ПК не подключён";
            }
            else if (_cooldowns.TryGetValue(effect.Id, out var nextAt) && nextAt > now)
            {
                rejectCode = "cooldown";
                rejectMessage = "Общий кулдаун ещё активен";
            }
            else
            {
                var eventId = Guid.NewGuid().ToString("N");
                var executeAt = now + ExecutionLeadMs;
                var nextAvailableAt = now + CooldownSecondsFor(effect) * 1000L;
                _cooldowns[effect.Id] = nextAvailableAt;
                if (effect.DurationSeconds > 0) _activeUntil[effect.Id] = executeAt + effect.DurationSeconds * 1000L;
                command = new EffectCommand("command", eventId, effect.Id, effect.DurationSeconds * 1000, Random.Shared.Next(), executeAt);
                AddEventLocked(new RoomEvent(eventId, now, controller.Name, effect.Id, effect.Label, "sent", "Отправлено на игровой ПК"));
            }
        }

        if (command is null)
        {
            await RejectAsync(controller, effectId, rejectCode!, rejectMessage!, ct);
            return;
        }

        await BroadcastAsync(new
        {
            type = "effectTriggered",
            command.EventId,
            command.EffectId,
            actor = controller.Name,
            command.ExecuteAt
        }, client => client.Role is "controller" or "admin", ct);
        await BroadcastAsync(command, client => client.Role == "agent", ct);
        await BroadcastSnapshotAsync(ct);
    }

    private async Task SetPausedAsync(ClientConnection controller, bool paused, CancellationToken ct)
    {
        lock (_gate)
        {
            _paused = paused;
            AddEventLocked(new RoomEvent(Guid.NewGuid().ToString("N"), Now(), controller.Name, "system_pause", paused ? "Экстренная пауза" : "Система возобновлена", "executed", paused ? "Все эффекты остановлены" : "Команды снова доступны"));
        }

        if (paused)
        {
            await BroadcastAsync(new { type = "cancelAll" }, client => client.Role == "agent", ct);
        }
        await BroadcastSnapshotAsync(ct);
    }

    private async Task BlockUserAsync(ClientConnection admin, string targetClientId, int blockSeconds, CancellationToken ct)
    {
        if (blockSeconds != -1 && blockSeconds is < 0 or > 3600)
        {
            await SendAsync(admin, new { type = "error", code = "invalid_block_duration", message = "Блокировка должна быть от 0 до 3600 секунд или навсегда" }, ct);
            return;
        }

        string? targetName = null;
        string detail = "";
        lock (_gate)
        {
            var target = _clients.Values.FirstOrDefault(client => client.Id == targetClientId && client.Role == "controller");
            if (target is not null)
            {
                targetName = target.Name;
                if (blockSeconds == 0)
                {
                    _blockedUsersUntil.Remove(target.Name);
                    detail = "Пользователь разблокирован";
                }
                else if (blockSeconds == -1)
                {
                    _blockedUsersUntil[target.Name] = long.MaxValue;
                    detail = "Пользователь заблокирован до ручной разблокировки";
                }
                else
                {
                    _blockedUsersUntil[target.Name] = Now() + blockSeconds * 1000L;
                    detail = $"Пользователь заблокирован на {blockSeconds} секунд";
                }
                AddEventLocked(new RoomEvent(Guid.NewGuid().ToString("N"), Now(), admin.Name, "user_block", $"Блокировка: {target.Name}", "executed", detail));
            }
        }

        if (targetName is null)
        {
            await SendAsync(admin, new { type = "error", code = "user_not_found", message = "Пользователь уже отключился" }, ct);
            return;
        }
        await BroadcastSnapshotAsync(ct);
    }

    private async Task SetCooldownAsync(ClientConnection admin, string effectId, int cooldownSeconds, CancellationToken ct)
    {
        var effect = Effects.FirstOrDefault(item => item.Id.Equals(effectId, StringComparison.OrdinalIgnoreCase));
        if (effect is null || cooldownSeconds is < 0 or > 3600)
        {
            await SendAsync(admin, new { type = "error", code = "invalid_cooldown", message = "Кулдаун должен быть от 0 до 3600 секунд" }, ct);
            return;
        }

        lock (_gate)
        {
            _cooldownOverrides[effect.Id] = cooldownSeconds;
            AddEventLocked(new RoomEvent(Guid.NewGuid().ToString("N"), Now(), admin.Name, "cooldown_change", $"Кулдаун: {effect.Label}", "executed", $"Установлено {cooldownSeconds} сек."));
        }
        await BroadcastSnapshotAsync(ct);
    }

    private async Task AckAsync(string eventId, string status, string? detail, CancellationToken ct)
    {
        lock (_gate)
        {
            var index = _events.FindIndex(item => item.EventId == eventId);
            if (index >= 0)
            {
                var current = _events[index];
                _events[index] = current with { Status = status, Detail = detail ?? (status == "executed" ? "Выполнено игровым ПК" : "Ошибка выполнения") };
            }
        }
        await BroadcastSnapshotAsync(ct);
    }

    private Task RejectAsync(ClientConnection client, string effectId, string code, string message, CancellationToken ct) =>
        SendAsync(client, new { type = "triggerRejected", effectId, code, message, serverTime = Now() }, ct);

    private object Snapshot()
    {
        lock (_gate)
        {
            var now = Now();
            var controllers = _clients.Values
                .Where(client => client.Role is "controller" or "admin" && client.Socket.State == WebSocketState.Open)
                .Select(client =>
                {
                    var storedUntil = _blockedUsersUntil.GetValueOrDefault(client.Name);
                    var blockedPermanently = storedUntil == long.MaxValue;
                    return new
                    {
                        client.Id,
                        client.Name,
                        client.Role,
                        blockedUntil = blockedPermanently || storedUntil > now ? storedUntil : 0,
                        blockedPermanently
                    };
                })
                .OrderBy(client => client.Name)
                .ToArray();

            return new
            {
                type = "snapshot",
                roomCode = RoomCode,
                paused = _paused,
                agentConnected = _clients.Values.Any(client => client.Role == "agent" && client.Socket.State == WebSocketState.Open),
                controllers,
                serverTime = now,
                effects = Effects.Select(effect => new
                {
                    effect.Id,
                    effect.Label,
                    effect.Category,
                    effect.Icon,
                    cooldownSeconds = CooldownSecondsFor(effect),
                    effect.DurationSeconds,
                    nextAvailableAt = _cooldowns.GetValueOrDefault(effect.Id),
                    activeUntil = _activeUntil.GetValueOrDefault(effect.Id) > now ? _activeUntil[effect.Id] : 0
                }),
                events = _events.OrderByDescending(item => item.Timestamp).Take(24)
            };
        }
    }

    private async Task BroadcastSnapshotAsync(CancellationToken ct) =>
        await BroadcastAsync(Snapshot(), client => client.Role is "controller" or "admin", ct);

    private async Task BroadcastAsync(object payload, Func<ClientConnection, bool> predicate, CancellationToken ct)
    {
        var targets = _clients.Values.Where(predicate).ToArray();
        await Task.WhenAll(targets.Select(client => SendAsync(client, payload, ct)));
    }

    private async Task SendAsync(ClientConnection client, object payload, CancellationToken ct)
    {
        if (client.Socket.State != WebSocketState.Open) return;
        var bytes = JsonSerializer.SerializeToUtf8Bytes(payload, _json);
        var lockTaken = false;
        try
        {
            await client.SendLock.WaitAsync(ct);
            lockTaken = true;
            if (client.Socket.State == WebSocketState.Open)
                await client.Socket.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
        }
        catch (WebSocketException exception)
        {
            logger.LogWarning("WebSocket send failed: role={Role}, name={Name}, error={Error}", client.Role, client.Name, exception.Message);
            try { client.Socket.Abort(); } catch { }
        }
        catch (OperationCanceledException) { }
        finally
        {
            if (lockTaken) client.SendLock.Release();
        }
    }

    private void AddEventLocked(RoomEvent roomEvent)
    {
        _events.Add(roomEvent);
        if (_events.Count > 100) _events.RemoveRange(0, _events.Count - 100);
    }

    private int CooldownSecondsFor(EffectDefinition effect) =>
        _cooldownOverrides.GetValueOrDefault(effect.Id, effect.CooldownSeconds);

    private static long Now() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}

sealed record ClientConnection(string Id, string Role, string Name, WebSocket Socket)
{
    public SemaphoreSlim SendLock { get; } = new(1, 1);
}

sealed record EffectDefinition(string Id, string Label, string Category, string Icon, int CooldownSeconds, int DurationSeconds);
sealed record EffectCommand(string Type, string EventId, string EffectId, int DurationMs, int Seed, long ExecuteAt);
sealed record RoomEvent(string EventId, long Timestamp, string Actor, string EffectId, string EffectLabel, string Status, string Detail);
sealed record ClientMessage(string? Type, string? Token, string? EffectId, bool? Paused, string? EventId, string? Status, string? Detail, long? ClientTime, string? TargetClientId, int? CooldownSeconds, int? BlockSeconds);

public partial class Program { }
