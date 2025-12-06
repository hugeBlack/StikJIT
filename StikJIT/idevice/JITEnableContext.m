//
//  JITEnableContext.m
//  StikJIT
//
//  Created by s s on 2025/3/28.
//
#include "idevice.h"
#include <arpa/inet.h>
#include <signal.h>
#include <stdlib.h>

#include "heartbeat.h"
#include "jit.h"
#include "applist.h"
#include "profiles.h"

#include "JITEnableContext.h"
#import "StikDebug-Swift.h"
#include <os/lock.h>
#import <pthread.h>

JITEnableContext* sharedJITContext = nil;

@implementation JITEnableContext {
    IdeviceProviderHandle* provider;
    dispatch_queue_t syslogQueue;
    BOOL syslogStreaming;
    SyslogRelayClientHandle *syslogClient;
    SyslogLineHandler syslogLineHandler;
    SyslogErrorHandler syslogErrorHandler;
    dispatch_queue_t processInspectorQueue;
    
    int heartbeatToken;
    NSError* lastHeartbeatError;
    os_unfair_lock heartbeatLock;
    BOOL heartbeatRunning;
    dispatch_semaphore_t heartbeatSemaphore;

}

+ (instancetype)shared {
    if (!sharedJITContext) {
        sharedJITContext = [[JITEnableContext alloc] init];
    }
    return sharedJITContext;
}

- (instancetype)init {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* logURL = [docPathUrl URLByAppendingPathComponent:@"idevice_log.txt"];
    idevice_init_logger(Info, Debug, (char*)logURL.path.UTF8String);
    syslogQueue = dispatch_queue_create("com.stik.syslogrelay.queue", DISPATCH_QUEUE_SERIAL);
    syslogStreaming = NO;
    syslogClient = NULL;
    dispatch_queue_attr_t qosAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    processInspectorQueue = dispatch_queue_create("com.stikdebug.processInspector", qosAttr);
    
    heartbeatToken = 0;
    heartbeatLock = OS_UNFAIR_LOCK_INIT;
    heartbeatRunning = NO;
    heartbeatSemaphore = NULL;
    lastHeartbeatError = nil;

    return self;
}

- (NSError*)errorWithStr:(NSString*)str code:(int)code {
    return [NSError errorWithDomain:@"StikJIT"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: str }];
}

- (LogFuncC)createCLogger:(LogFunc)logger {
    return ^(const char* format, ...) {
        va_list args;
        va_start(args, format);
        NSString* fmt = [NSString stringWithCString:format encoding:NSASCIIStringEncoding];
        NSString* message = [[NSString alloc] initWithFormat:fmt arguments:args];
        NSLog(@"%@", message);

        if ([message containsString:@"ERROR"] || [message containsString:@"Error"]) {
            [[LogManagerBridge shared] addErrorLog:message];
        } else if ([message containsString:@"WARNING"] || [message containsString:@"Warning"]) {
            [[LogManagerBridge shared] addWarningLog:message];
        } else if ([message containsString:@"DEBUG"]) {
            [[LogManagerBridge shared] addDebugLog:message];
        } else {
            [[LogManagerBridge shared] addInfoLog:message];
        }

        if (logger) {
            logger(message);
        }
        va_end(args);
    };
}

- (IdevicePairingFile*)getPairingFileWithError:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* pairingFileURL = [docPathUrl URLByAppendingPathComponent:@"pairingFile.plist"];

    if (![fm fileExistsAtPath:pairingFileURL.path]) {
        NSLog(@"Pairing file not found!");
        *error = [self errorWithStr:@"Pairing file not found!" code:-17];
        return nil;
    }

    IdevicePairingFile* pairingFile = NULL;
    IdeviceFfiError* err = idevice_pairing_file_read(pairingFileURL.fileSystemRepresentation, &pairingFile);
    if (err) {
        *error = [self errorWithStr:@"Failed to read pairing file!" code:err->code];
        return nil;
    }
    return pairingFile;
}

// only block until first heartbeat is completed or failed.
- (BOOL)startHeartbeat:(NSError**)err {
    os_unfair_lock_lock(&heartbeatLock);
    
    // If heartbeat is already running, wait for it to complete
    if (heartbeatRunning) {
        dispatch_semaphore_t waitSemaphore = heartbeatSemaphore;
        os_unfair_lock_unlock(&heartbeatLock);
        
        if (waitSemaphore) {
            dispatch_semaphore_wait(waitSemaphore, DISPATCH_TIME_FOREVER);
            dispatch_semaphore_signal(waitSemaphore);
        }
        *err = lastHeartbeatError;
        return *err == nil;
    }
    
    // Mark heartbeat as running
    heartbeatRunning = YES;
    heartbeatSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_t completionSemaphore = heartbeatSemaphore;
    os_unfair_lock_unlock(&heartbeatLock);
    
    IdevicePairingFile* pairingFile = [self getPairingFileWithError:err];
    if (*err) {
        os_unfair_lock_lock(&heartbeatLock);
        heartbeatRunning = NO;
        heartbeatSemaphore = NULL;
        os_unfair_lock_unlock(&heartbeatLock);
        dispatch_semaphore_signal(completionSemaphore);
        return NO;
    }

    globalHeartbeatToken++;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block bool completionCalled = false;
    HeartbeatCompletionHandlerC Ccompletion = ^(int result, const char *message) {
        if(completionCalled) {
            return;
        }
        if (result != 0) {
            *err = [self errorWithStr:[NSString stringWithCString:message
                                                         encoding:NSASCIIStringEncoding] code:result];
            self->lastHeartbeatError = *err;
        } else {
            self->lastHeartbeatError = nil;
        }
        completionCalled = true;

        dispatch_semaphore_signal(semaphore);
    };
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        startHeartbeat(
            pairingFile,
            &self->provider,
                       globalHeartbeatToken,Ccompletion
        );
    });
    // allow 2 seconds for heartbeat, otherwise we declare timeout
    intptr_t isTimeout = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (uint64_t)(5 * NSEC_PER_SEC)));
    if(isTimeout) {
        Ccompletion(-1, "Heartbeat failed to complete in reasonable time.");
    } else {
        NSLog(@"Start heartbeat success %p", pthread_self());
    }

    os_unfair_lock_lock(&heartbeatLock);
    heartbeatRunning = NO;
    heartbeatSemaphore = NULL;
    os_unfair_lock_unlock(&heartbeatLock);
    dispatch_semaphore_signal(completionSemaphore);
    
    return *err == nil;
}

- (BOOL)ensureHeartbeatWithError:(NSError**)err {
    // if it's 15s after last heartbeat, we restart heartbeat.
    if((!lastHeartbeatDate || [[NSDate now] timeIntervalSinceDate:lastHeartbeatDate] > 15)) {
        return [self startHeartbeat:err];
    }
    return YES;
}

- (BOOL)debugAppWithBundleID:(NSString*)bundleID logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback {
    NSError* err = nil;
    [self ensureHeartbeatWithError:&err];
    if(err) {
        logger(err.localizedDescription);
        return NO;
    }
    
    return debug_app(provider,
                     [bundleID UTF8String],
                     [self createCLogger:logger], jsCallback) == 0;
}

- (BOOL)debugAppWithPID:(int)pid logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback {
    NSError* err = nil;
    [self ensureHeartbeatWithError:&err];
    if(err) {
        logger(err.localizedDescription);
        return NO;
    }
    
    return debug_app_pid(provider,
                     pid,
                     [self createCLogger:logger], jsCallback) == 0;
}

- (NSDictionary<NSString*, NSString*>*)getAppListWithError:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSString*>* apps = list_installed_apps(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (NSDictionary<NSString*, NSString*>*)getAllAppsWithError:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSString*>* apps = list_all_apps(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (NSDictionary<NSString*, NSString*>*)getHiddenSystemAppsWithError:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSString*>* apps = list_hidden_system_apps(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (UIImage*)getAppIconWithBundleId:(NSString*)bundleId error:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }

    NSString* errorStr = nil;
    UIImage* icon = getAppIcon(provider, bundleId, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return icon;
}

- (BOOL)launchAppWithoutDebug:(NSString*)bundleID logger:(LogFunc)logger {
    NSError* err = nil;
    [self ensureHeartbeatWithError:&err];
    if(err) {
        logger(err.localizedDescription);
        return NO;
    }

    int result = launch_app_via_proxy(provider,
                                      [bundleID UTF8String],
                                      [self createCLogger:logger]);
    return result == 0;
}

- (void)startSyslogRelayWithHandler:(SyslogLineHandler)lineHandler
                             onError:(SyslogErrorHandler)errorHandler
{
    NSError* error = nil;
    [self ensureHeartbeatWithError:&error];
    if(error) {
        errorHandler(error);
        return;
    }
    if (!lineHandler || syslogStreaming) {
        return;
    }

    syslogStreaming = YES;
    syslogLineHandler = [lineHandler copy];
    syslogErrorHandler = [errorHandler copy];

    __weak typeof(self) weakSelf = self;
    dispatch_async(syslogQueue, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        SyslogRelayClientHandle *client = NULL;
        IdeviceFfiError *err = syslog_relay_connect_tcp(strongSelf->provider, &client);
        if (err != NULL) {
            NSString *message = err->message ? [NSString stringWithCString:err->message encoding:NSASCIIStringEncoding] : @"Failed to connect to syslog relay";
            NSError *nsError = [strongSelf errorWithStr:message code:err->code];
            idevice_error_free(err);
            [strongSelf handleSyslogFailure:nsError];
            return;
        }

        strongSelf->syslogClient = client;

        while (strongSelf && strongSelf->syslogStreaming) {
            char *message = NULL;
            IdeviceFfiError *nextErr = syslog_relay_next(client, &message);
            if (nextErr != NULL) {
                NSString *errMsg = nextErr->message ? [NSString stringWithCString:nextErr->message encoding:NSASCIIStringEncoding] : @"Syslog relay read failed";
                NSError *nsError = [strongSelf errorWithStr:errMsg code:nextErr->code];
                idevice_error_free(nextErr);
                if (message) { idevice_string_free(message); }
                [strongSelf handleSyslogFailure:nsError];
                client = NULL;
                break;
            }

            if (!message) {
                continue;
            }

            NSString *line = [NSString stringWithCString:message encoding:NSUTF8StringEncoding];
            idevice_string_free(message);
            if (!line || !strongSelf->syslogLineHandler) {
                continue;
            }

            SyslogLineHandler handlerCopy = strongSelf->syslogLineHandler;
            if (handlerCopy) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handlerCopy(line);
                });
            }
        }

        if (client) {
            syslog_relay_client_free(client);
        }

        strongSelf->syslogClient = NULL;
        strongSelf->syslogStreaming = NO;
        strongSelf->syslogLineHandler = nil;
        strongSelf->syslogErrorHandler = nil;
    });
}

- (void)stopSyslogRelay {
    if (!syslogStreaming) {
        return;
    }

    syslogStreaming = NO;
    syslogLineHandler = nil;
    syslogErrorHandler = nil;

    dispatch_async(syslogQueue, ^{
        if (self->syslogClient) {
            syslog_relay_client_free(self->syslogClient);
            self->syslogClient = NULL;
        }
    });
}

- (void)handleSyslogFailure:(NSError *)error {
    syslogStreaming = NO;
    if (syslogClient) {
        syslog_relay_client_free(syslogClient);
        syslogClient = NULL;
    }
    SyslogErrorHandler errorCopy = syslogErrorHandler;
    syslogLineHandler = nil;
    syslogErrorHandler = nil;

    if (errorCopy) {
        dispatch_async(dispatch_get_main_queue(), ^{
            errorCopy(error);
        });
    }
}

- (NSArray<NSData*>*)fetchAllProfiles:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }
    
    return fetchAppProfiles(provider, error);
}

- (BOOL)removeProfileWithUUID:(NSString*)uuid error:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }
    
    return removeProfile(provider, uuid, error);
}

- (BOOL)addProfile:(NSData*)profile error:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }
    return addProfile(provider, profile, error);
}

- (void)dealloc {
    [self stopSyslogRelay];
    if (provider) {
        idevice_provider_free(provider);
    }
}

- (NSArray<NSDictionary*>*)fetchProcessesViaAppServiceWithError:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }
    
    IdeviceProviderHandle *providerToUse = provider;
    CoreDeviceProxyHandle *coreProxy = NULL;
    AdapterHandle *adapter = NULL;
    AdapterStreamHandle *stream = NULL;
    RsdHandshakeHandle *handshake = NULL;
    AppServiceHandle *appService = NULL;
    ProcessTokenC *processes = NULL;
    uintptr_t count = 0;
    NSMutableArray *result = nil;
    IdeviceFfiError *ffiError = NULL;

    do {

        ffiError = core_device_proxy_connect(providerToUse, &coreProxy);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to connect CoreDeviceProxy"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        uint16_t rsdPort = 0;
        ffiError = core_device_proxy_get_server_rsd_port(coreProxy, &rsdPort);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to resolve RSD port"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = core_device_proxy_create_tcp_adapter(coreProxy, &adapter);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to create adapter"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        coreProxy = NULL;
        ffiError = adapter_connect(adapter, rsdPort, (ReadWriteOpaque **)&stream);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Adapter connect failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = rsd_handshake_new((ReadWriteOpaque *)stream, &handshake);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "RSD handshake failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        stream = NULL;
        ffiError = app_service_connect_rsd(adapter, handshake, &appService);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to open AppService"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = app_service_list_processes(appService, &processes, &count);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to list processes"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        result = [NSMutableArray arrayWithCapacity:count];
        for (uintptr_t idx = 0; idx < count; idx++) {
            ProcessTokenC proc = processes[idx];
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"pid"] = @(proc.pid);
            if (proc.executable_url) {
                entry[@"path"] = [NSString stringWithUTF8String:proc.executable_url];
            }
            [result addObject:entry];
        }
    } while (0);

    if (processes && count > 0) {
        app_service_free_process_list(processes, count);
    }
    if (appService) {
        app_service_free(appService);
    }
    if (handshake) {
        rsd_handshake_free(handshake);
    }
    if (stream) {
        adapter_stream_close(stream);
    }
    if (adapter) {
        adapter_free(adapter);
    }
    if (coreProxy) {
        core_device_proxy_free(coreProxy);
    }
    return result;
}

- (NSArray<NSDictionary*>*)_fetchProcessListLocked:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }
    return [self fetchProcessesViaAppServiceWithError:error];
}

- (NSArray<NSDictionary*>*)fetchProcessListWithError:(NSError**)error {
    __block NSArray *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(processInspectorQueue, ^{
        result = [self _fetchProcessListLocked:&localError];
    });
    if (error && localError) {
        *error = localError;
    }
    return result;
}

- (BOOL)killProcessWithPID:(int)pid error:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return nil;
    }
    
    IdeviceProviderHandle *providerToUse = provider;
    CoreDeviceProxyHandle *coreProxy = NULL;
    AdapterHandle *adapter = NULL;
    AdapterStreamHandle *stream = NULL;
    RsdHandshakeHandle *handshake = NULL;
    AppServiceHandle *appService = NULL;
    SignalResponseC *signalResponse = NULL;
    IdeviceFfiError *ffiError = NULL;
    BOOL success = NO;

    do {
        ffiError = core_device_proxy_connect(providerToUse, &coreProxy);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to connect CoreDeviceProxy"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        uint16_t rsdPort = 0;
        ffiError = core_device_proxy_get_server_rsd_port(coreProxy, &rsdPort);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to resolve RSD port"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = core_device_proxy_create_tcp_adapter(coreProxy, &adapter);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to create adapter"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        coreProxy = NULL;
        ffiError = adapter_connect(adapter, rsdPort, (ReadWriteOpaque **)&stream);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Adapter connect failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = rsd_handshake_new((ReadWriteOpaque *)stream, &handshake);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "RSD handshake failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        stream = NULL;
        ffiError = app_service_connect_rsd(adapter, handshake, &appService);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to open AppService"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = app_service_send_signal(appService, (uint32_t)pid, SIGKILL, &signalResponse);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to kill process"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }
        success = YES;
    } while (0);

    if (signalResponse) {
        app_service_free_signal_response(signalResponse);
    }
    if (appService) {
        app_service_free(appService);
    }
    if (handshake) {
        rsd_handshake_free(handshake);
    }
    if (stream) {
        adapter_stream_close(stream);
    }
    if (adapter) {
        adapter_free(adapter);
    }
    if (coreProxy) {
        core_device_proxy_free(coreProxy);
    }
    return success;
}

- (NSUInteger)getMountedDeviceCount:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return NO;
    }
    return getMountedDeviceCount(provider, error);
}
- (NSInteger)mountPersonalDDIWithImagePath:(NSString*)imagePath trustcachePath:(NSString*)trustcachePath manifestPath:(NSString*)manifestPath error:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) {
        return 0;
    }
    IdevicePairingFile* pairing = [self getPairingFileWithError:error];
    if(*error) {
        return 0;
    }
    return mountPersonalDDI(provider, pairing, imagePath, trustcachePath, manifestPath, error);
}

@end
