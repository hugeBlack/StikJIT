//
//  IDeviceJSBridgeProcessControl.m
//  StikJIT
//
//  Created by s s on 2025/4/25.
//
@import Foundation;
#import "JSSupport.h"
@implementation IDeviceJSBridge (ProcessControl)

- (void)process_control_newWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
        
    int clientId = [body[@"server"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != remote_server_free) {
        replyHandler(nil, @"Invalid remote server handle");
        return;
    }
    IDeviceHandle* clientHandleObj = handles[@(clientId)];
    RemoteServerHandle* remote_server = clientHandleObj.handle;
    
    ProcessControlHandle *process_control = NULL;
    IdeviceFfiError* err = process_control_new(remote_server, &process_control);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }
    
    int handleId = [self registerIdeviceHandle:process_control freeFunc:(void*)process_control_free];
    replyHandler(@(handleId), nil);
}

- (void)process_control_launch_appWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
        
    int clientId = [body[@"handle"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != process_control_free) {
        replyHandler(nil, @"Invalid process control handle");
        return;
    }
    IDeviceHandle* clientHandleObj = handles[@(clientId)];
    ProcessControlHandle* process_control = clientHandleObj.handle;
    
    NSString* bundleId = body[@"bundle_id"];
    if(![bundleId isKindOfClass:NSString.class]) {
        replyHandler(nil, @"Invalid bundle id");
        return;
    }
    
    NSArray* envVars = body[@"env_vars"];
    int envVarsCount = 0;
    const char** envVarsCharArr = cstrArrFromNSArray(envVars, &envVarsCount);
    
    NSArray* arguments = body[@"arguments"];
    int argumentsCount = 0;
    const char** argumentsCharArr = cstrArrFromNSArray(arguments, &argumentsCount);
    
    bool startSuspended = [body[@"start_suspended"] boolValue];
    bool killExisting = [body[@"kill_existing"] boolValue];
    
    uint64_t pid = 0;
    IdeviceFfiError* err = process_control_launch_app(process_control, [bundleId UTF8String], envVarsCharArr, envVarsCount, argumentsCharArr, argumentsCount,
                                                      startSuspended, killExisting, &pid);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }
    if(envVarsCharArr) {
        free(envVarsCharArr);
    }
    
    if(argumentsCharArr) {
        free(argumentsCharArr);
    }
    
    replyHandler(@(pid), nil);
}

- (void)process_control_disable_memory_limitWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
        
    int clientId = [body[@"handle"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != process_control_free) {
        replyHandler(nil, @"Invalid process control handle");
    }
    IDeviceHandle* clientHandleObj = handles[@(clientId)];
    ProcessControlHandle* process_control = clientHandleObj.handle;
    
    uint64_t pid = [body[@"pid"] unsignedLongLongValue];
    if(pid == 0) {
        replyHandler(nil, @"Invalid pid");
        return;
    }
    
    IdeviceFfiError* err = process_control_disable_memory_limit(process_control, pid);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }
    
    replyHandler(@(YES), nil);
}

- (void)process_control_kill_appWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
        
    int clientId = [body[@"handle"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != process_control_free) {
        replyHandler(nil, @"Invalid process control handle");
    }
    IDeviceHandle* clientHandleObj = handles[@(clientId)];
    ProcessControlHandle* process_control = clientHandleObj.handle;
    
    uint64_t pid = [body[@"pid"] unsignedLongLongValue];
    if(pid == 0) {
        replyHandler(nil, @"Invalid pid");
        return;
    }
    
    IdeviceFfiError* err = process_control_kill_app(process_control, pid);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }
    
    replyHandler(@(YES), nil);
}

@end
