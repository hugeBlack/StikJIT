//
//  IDeviceJSBridgeAdapter.m
//  StikJIT
//
//  Created by s s on 2025/4/25.
//
@import Foundation;
#import "JSSupport.h"

@implementation IDeviceJSBridge (Adapter)

- (void)adapter_connectWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
        
    int clientId = [body[@"adapter"] intValue];
    if(!handles[@(clientId)] || handles[@(clientId)].freeFunc != adapter_free) {
        replyHandler(nil, @"Invalid adapter handle");
        return;
    }
    
    int port = [body[@"port"] intValue];
    if(port < 0 || port > 65536 ) {
        replyHandler(nil, @"Invalid port");
        return;
    }
    IDeviceHandle* clientHandleObj = handles[@(clientId)];
    AdapterHandle* handle = clientHandleObj.handle;
    AdapterStreamHandle *stream = NULL;
    IdeviceFfiError* err = adapter_connect(handle, port, (ReadWriteOpaque **)&stream);
    if (err) {
        replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
        return;
    }
    int handleId = [self registerIdeviceHandle:stream freeFunc:(void *)adapter_stream_close];
    replyHandler(@(handleId), nil);
}

@end
