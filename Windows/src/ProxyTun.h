#ifndef PROXYTUN_H
#define PROXYTUN_H

#include <windows.h>

#ifdef PROXYTUN_EXPORTS
#define PROXYTUN_API __declspec(dllexport)
#else
#define PROXYTUN_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*LogCallback)(const char* message);
typedef void (*ConnectionCallback)(const char* process_name, DWORD pid, const char* dest_ip, UINT16 dest_port, const char* proxy_info);

typedef enum {
    PROXY_TYPE_HTTP = 0,
    PROXY_TYPE_SOCKS5 = 1
} ProxyType;

typedef enum {
    RULE_ACTION_PROXY = 0,
    RULE_ACTION_DIRECT = 1,
    RULE_ACTION_BLOCK = 2
} RuleAction;

typedef enum {
    RULE_PROTOCOL_TCP = 0,
    RULE_PROTOCOL_UDP = 1,
    RULE_PROTOCOL_BOTH = 2
} RuleProtocol;

PROXYTUN_API UINT32 ProxyTun_AddRule(const char* process_name, const char* target_hosts, const char* target_ports, RuleProtocol protocol, RuleAction action);
PROXYTUN_API BOOL ProxyTun_EnableRule(UINT32 rule_id);
PROXYTUN_API BOOL ProxyTun_DisableRule(UINT32 rule_id);
PROXYTUN_API BOOL ProxyTun_DeleteRule(UINT32 rule_id);
PROXYTUN_API BOOL ProxyTun_EditRule(UINT32 rule_id, const char* process_name, const char* target_hosts, const char* target_ports, RuleProtocol protocol, RuleAction action);
PROXYTUN_API BOOL ProxyTun_MoveRuleToPosition(UINT32 rule_id, UINT32 new_position);  // Move rule to specific position (1=first, 2=second, etc)
PROXYTUN_API UINT32 ProxyTun_GetRulePosition(UINT32 rule_id);  // Get current position of rule in list (1-based)
PROXYTUN_API BOOL ProxyTun_SetProxyConfig(ProxyType type, const char* proxy_ip, UINT16 proxy_port, const char* username, const char* password);  // proxy_ip can be IP address or hostname
PROXYTUN_API void ProxyTun_SetDnsViaProxy(BOOL enable);
PROXYTUN_API void ProxyTun_SetLocalhostViaProxy(BOOL enable);
PROXYTUN_API void ProxyTun_SetLogCallback(LogCallback callback);
PROXYTUN_API void ProxyTun_SetConnectionCallback(ConnectionCallback callback);
PROXYTUN_API void ProxyTun_SetTrafficLoggingEnabled(BOOL enable);
PROXYTUN_API void ProxyTun_ClearConnectionLogs(void);  // Clear connection history from memory
PROXYTUN_API BOOL ProxyTun_Start(void);
PROXYTUN_API BOOL ProxyTun_Stop(void);
PROXYTUN_API int ProxyTun_TestConnection(const char* target_host, UINT16 target_port, char* result_buffer, size_t buffer_size);

#ifdef __cplusplus
}
#endif

#endif
