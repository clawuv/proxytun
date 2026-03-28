using System;
using ProxyTun.GUI.Interop;

namespace ProxyTun.GUI.Services;

public class ProxyTunService : IDisposable
{
    private ProxyTunNative.LogCallback? _logCallback;
    private ProxyTunNative.ConnectionCallback? _connectionCallback;
    private bool _isRunning;

    public event Action<string>? LogReceived;
    public event Action<string, uint, string, ushort, string>? ConnectionReceived;

    public ProxyTunService()
    {
        _logCallback = OnLogReceived;
        _connectionCallback = OnConnectionReceived;

        ProxyTunNative.ProxyTun_SetLogCallback(_logCallback);
        ProxyTunNative.ProxyTun_SetConnectionCallback(_connectionCallback);
    }

    private void OnLogReceived(string message)
    {
        LogReceived?.Invoke(message);
    }

    private void OnConnectionReceived(string processName, uint pid, string destIp, ushort destPort, string proxyInfo)
    {
        ConnectionReceived?.Invoke(processName, pid, destIp, destPort, proxyInfo);
    }

    public bool Start()
    {
        if (_isRunning)
            return true;

        _isRunning = ProxyTunNative.ProxyTun_Start();
        return _isRunning;
    }

    public bool Stop()
    {
        if (!_isRunning)
            return true;

        _isRunning = !ProxyTunNative.ProxyTun_Stop();
        return !_isRunning;
    }

    public bool SetProxyConfig(string type, string ip, ushort port, string username, string password)
    {
        var proxyType = type.ToUpper() == "HTTP"
            ? ProxyTunNative.ProxyType.HTTP
            : ProxyTunNative.ProxyType.SOCKS5;

        return ProxyTunNative.ProxyTun_SetProxyConfig(proxyType, ip, port, username, password);
    }

    public uint AddRule(string processName, string targetHosts, string targetPorts, string protocol, string action)
    {
        var ruleAction = action.ToUpper() switch
        {
            "DIRECT" => ProxyTunNative.RuleAction.DIRECT,
            "BLOCK" => ProxyTunNative.RuleAction.BLOCK,
            _ => ProxyTunNative.RuleAction.PROXY
        };

        var ruleProtocol = protocol.ToUpper() switch
        {
            "UDP" => ProxyTunNative.RuleProtocol.UDP,
            "BOTH" => ProxyTunNative.RuleProtocol.BOTH,
            "TCP+UDP" => ProxyTunNative.RuleProtocol.BOTH,
            _ => ProxyTunNative.RuleProtocol.TCP
        };

        return ProxyTunNative.ProxyTun_AddRule(processName, targetHosts, targetPorts, ruleProtocol, ruleAction);
    }

    public bool EnableRule(uint ruleId)
    {
        return ProxyTunNative.ProxyTun_EnableRule(ruleId);
    }

    public bool DisableRule(uint ruleId)
    {
        return ProxyTunNative.ProxyTun_DisableRule(ruleId);
    }

    public bool DeleteRule(uint ruleId)
    {
        return ProxyTunNative.ProxyTun_DeleteRule(ruleId);
    }

    public bool EditRule(uint ruleId, string processName, string targetHosts, string targetPorts, string protocol, string action)
    {
        var ruleAction = action.ToUpper() switch
        {
            "DIRECT" => ProxyTunNative.RuleAction.DIRECT,
            "BLOCK" => ProxyTunNative.RuleAction.BLOCK,
            _ => ProxyTunNative.RuleAction.PROXY
        };

        var ruleProtocol = protocol.ToUpper() switch
        {
            "UDP" => ProxyTunNative.RuleProtocol.UDP,
            "BOTH" => ProxyTunNative.RuleProtocol.BOTH,
            "TCP+UDP" => ProxyTunNative.RuleProtocol.BOTH,
            _ => ProxyTunNative.RuleProtocol.TCP
        };

        return ProxyTunNative.ProxyTun_EditRule(ruleId, processName, targetHosts, targetPorts, ruleProtocol, ruleAction);
    }

    public uint GetRulePosition(uint ruleId)
    {
        return ProxyTunNative.ProxyTun_GetRulePosition(ruleId);
    }

    public bool MoveRuleToPosition(uint ruleId, uint newPosition)
    {
        return ProxyTunNative.ProxyTun_MoveRuleToPosition(ruleId, newPosition);
    }

    public void SetDnsViaProxy(bool enable)
    {
        ProxyTunNative.ProxyTun_SetDnsViaProxy(enable);
    }

    public void SetLocalhostViaProxy(bool enable)
    {
        ProxyTunNative.ProxyTun_SetLocalhostViaProxy(enable);
    }

    public static void SetTrafficLoggingEnabled(bool enable)
    {
        ProxyTunNative.ProxyTun_SetTrafficLoggingEnabled(enable);
    }

    public string TestConnection(string targetHost, ushort targetPort)
    {
        var buffer = new System.Text.StringBuilder(4096);
        int result = ProxyTunNative.ProxyTun_TestConnection(
            targetHost,
            targetPort,
            buffer,
            (UIntPtr)buffer.Capacity);

        return buffer.ToString();
    }

    public void Dispose()
    {
        if (_isRunning)
        {
            Stop(); // removing the threads, C code handle close no need to manually handle drives
        }
        GC.SuppressFinalize(this);
    }
}
