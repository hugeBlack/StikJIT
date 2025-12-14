//
//  IDeviceJSBridgeRemoteServer.m
//  StikJIT
//
//  Created by s s on 2025/4/25.
//
@import Foundation;
#import "JSSupport.h"

@implementation IDeviceJSBridge (RemoteServer)

- (void)remote_server_connect_rsdWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
        
    int clientId = [body[@"adapter"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != adapter_free) {
        replyHandler(nil, @"Invalid adapter handle");
        return;
    }
    IDeviceHandle* clientHandleObj = handles[@(clientId)];
    AdapterHandle* adapter = clientHandleObj.handle;
    
    int handshakeId = [body[@"handshake"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != rsd_handshake_free) {
        replyHandler(nil, @"Invalid handshake handle");
        return;
    }
    IDeviceHandle* handshakeHandleObj = handles[@(handshakeId)];
    RsdHandshakeHandle* handshake = handshakeHandleObj.handle;
    
    RemoteServerHandle *remote_server = NULL;
    IdeviceFfiError* err = remote_server_connect_rsd(adapter, handshake, &remote_server);
    [handles removeObjectForKey:@(clientId)];
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }
    
    int handleId = [self registerIdeviceHandle:remote_server freeFunc:(void*)remote_server_free];
    replyHandler(@(handleId), nil);
}


@end
