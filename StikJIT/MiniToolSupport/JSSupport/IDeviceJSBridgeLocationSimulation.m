//
//  IDeviceJSBridgeLocationSimulation.m
//  StikJIT
//
//  Created by s s on 2025/4/26.
//
@import Foundation;
#import "JSSupport.h"

@implementation IDeviceJSBridge (LocationSimulation)

- (void)location_simulation_newWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    int serverId = [body[@"server"] intValue];
    if (!handles[@(serverId)] || handles[@(serverId)].freeFunc != remote_server_free) {
        replyHandler(nil, @"Invalid remote server handle");
        return;
    }

    IDeviceHandle *serverHandleObj = handles[@(serverId)];
    RemoteServerHandle *server = serverHandleObj.handle;

    LocationSimulationHandle *simulation = NULL;
    IdeviceFfiError* err = location_simulation_new(server, &simulation);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    int handleId = [self registerIdeviceHandle:simulation freeFunc:(void *)location_simulation_free];
    replyHandler(@(handleId), nil);
}

- (void)location_simulation_clearWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    int handleId = [body[@"handle"] intValue];
    if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != location_simulation_free) {
        replyHandler(nil, @"Invalid LocationSimulationAdapterHandle");
        return;
    }

    IDeviceHandle *handleObj = handles[@(handleId)];
    LocationSimulationHandle *simulation = handleObj.handle;

    IdeviceFfiError* err = location_simulation_clear(simulation);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    replyHandler(@YES, nil);
}

- (void)location_simulation_setWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    int handleId = [body[@"handle"] intValue];
    if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != location_simulation_free) {
        replyHandler(nil, @"Invalid LocationSimulationAdapterHandle");
        return;
    }

    NSNumber *lat = body[@"latitude"];
    NSNumber *lon = body[@"longitude"];
    if (![lat isKindOfClass:NSNumber.class] || ![lon isKindOfClass:NSNumber.class]) {
        replyHandler(nil, @"latitude or longitude is invalid");
        return;
    }

    IDeviceHandle *handleObj = handles[@(handleId)];
    LocationSimulationHandle *simulation = handleObj.handle;

    IdeviceFfiError* err = location_simulation_set(simulation, lat.doubleValue, lon.doubleValue);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }

    replyHandler(@YES, nil);
}

@end
