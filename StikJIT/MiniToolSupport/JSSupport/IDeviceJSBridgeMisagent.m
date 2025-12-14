//
//  IDeviceJSBridgeMisagent.m
//  StikJIT
//
//  Created by s s on 2025/4/26.
//
@import Foundation;
#import "JSSupport.h"

@implementation IDeviceJSBridge (Misagent)

- (void)misagent_connectWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    NSError* heartbeatErr = nil;
    [JITEnableContext.shared ensureHeartbeatWithError:&heartbeatErr];
    if(heartbeatErr) {
        replyHandler(nil, heartbeatErr.localizedDescription);
        return;
    }
    
    IdeviceProviderHandle* provider = [JITEnableContext.shared getTcpProviderHandle];

    MisagentClientHandle* client = NULL;
    IdeviceFfiError* err = misagent_connect(provider, &client);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    int clientHandleId = [self registerIdeviceHandle:client freeFunc:(void*)misagent_client_free];
    replyHandler(@(clientHandleId), nil);
}

- (void)misagent_installWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    int clientId = [body[@"handle"] intValue];
    int dataHandleId = [body[@"data_handle"] intValue];

    if (!handles[@(clientId)] || handles[@(clientId)].freeFunc != misagent_client_free) {
        replyHandler(nil, @"Invalid misagent client handle");
        return;
    }

    if (!dataPool[@(dataHandleId)]) {
        replyHandler(nil, @"Invalid NSData handle");
        return;
    }

    IDeviceHandle *clientHandleObj = handles[@(clientId)];
    MisagentClientHandle *client = clientHandleObj.handle;
    NSData *data = dataPool[@(dataHandleId)];

    IdeviceFfiError* err = misagent_install(client, data.bytes, data.length);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    replyHandler(@YES, nil);
}

- (void)misagent_removeWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    int clientId = [body[@"handle"] intValue];
    NSString *profileId = body[@"profile_id"];

    if (!handles[@(clientId)] || handles[@(clientId)].freeFunc != misagent_client_free) {
        replyHandler(nil, @"Invalid misagent client handle");
        return;
    }

    if (![profileId isKindOfClass:NSString.class]) {
        replyHandler(nil, @"Invalid profile_id");
        return;
    }

    IDeviceHandle *clientHandleObj = handles[@(clientId)];
    MisagentClientHandle *client = clientHandleObj.handle;

    IdeviceFfiError* err = misagent_remove(client, [profileId UTF8String]);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    replyHandler(@YES, nil);
}

- (void)misagent_copy_allWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    int clientId = [body[@"handle"] intValue];

    if (!handles[@(clientId)] || handles[@(clientId)].freeFunc != misagent_client_free) {
        replyHandler(nil, @"Invalid misagent client handle");
        return;
    }

    IDeviceHandle *clientHandleObj = handles[@(clientId)];
    MisagentClientHandle *client = clientHandleObj.handle;

    uint8_t **profiles = NULL;
    size_t *profile_lens = NULL;
    size_t count = 0;

    IdeviceFfiError* err = misagent_copy_all(client, &profiles, &profile_lens, &count);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    NSMutableArray *profileHandleIds = [NSMutableArray array];
    for (size_t i = 0; i < count; i++) {
        NSData *profileData = [NSData dataWithBytes:profiles[i] length:profile_lens[i]];
        free(profiles[i]);
        int nsdataHandleId = [self registerNSData:profileData];
        [profileHandleIds addObject:@(nsdataHandleId)];
    }

    misagent_free_profiles(profiles, profile_lens, count);

    replyHandler(profileHandleIds, nil);
}

@end
