//
//  IDeviceJSBridgeRSD.m
//  StikDebug
//
//  Created by s s on 2025/12/13.
//

@import Foundation;
#import "JSSupport.h"

static NSDictionary *RsdServiceToDictionary(const CRsdService *service) {
	if (!service) {
		return @{};
	}

	NSMutableArray<NSString *> *features = [[NSMutableArray alloc] initWithCapacity:service->features_count];
	for (size_t i = 0; i < service->features_count; ++i) {
		if (service->features[i]) {
			[features addObject:@(service->features[i])];
		}
	}

	NSString *name = service->name ? @(service->name) : @"";
	NSString *entitlement = service->entitlement ? @(service->entitlement) : @"";

	return @{
		@"name": name,
		@"entitlement": entitlement,
		@"port": @(service->port),
		@"uses_remote_xpc": @(service->uses_remote_xpc),
		@"features_count": @(service->features_count),
		@"features": features,
		@"service_version": @(service->service_version)
	};
}

@implementation IDeviceJSBridge (RSD)

- (void)rsd_handshake_newWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
	int socketId = [body[@"socket"] intValue];
	if (!handles[@(socketId)] || handles[@(socketId)].freeFunc != adapter_stream_close) {
		replyHandler(nil, @"Invalid socket handle");
		return;
	}
	IDeviceHandle *socketHandleObj = handles[@(socketId)];
	ReadWriteOpaque *socket = socketHandleObj.handle;

	RsdHandshakeHandle *handshake = NULL;
	IdeviceFfiError *err = rsd_handshake_new(socket, &handshake);
	[handles removeObjectForKey:@(socketId)];
	if (err) {
		replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
		return;
	}

	int handleId = [self registerIdeviceHandle:handshake freeFunc:(void *)rsd_handshake_free];
	replyHandler(@(handleId), nil);
}

- (void)rsd_get_protocol_versionWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
	int handleId = [body[@"handle"] intValue];
	if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != rsd_handshake_free) {
		replyHandler(nil, @"Invalid RSD handshake handle");
		return;
	}
	RsdHandshakeHandle *handshake = handles[@(handleId)].handle;

	size_t version = 0;
	IdeviceFfiError *err = rsd_get_protocol_version(handshake, &version);
	if (err) {
		replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
		return;
	}

	replyHandler(@(version), nil);
}

- (void)rsd_get_uuidWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
	int handleId = [body[@"handle"] intValue];
	if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != rsd_handshake_free) {
		replyHandler(nil, @"Invalid RSD handshake handle");
		return;
	}
	RsdHandshakeHandle *handshake = handles[@(handleId)].handle;

	char *uuid = NULL;
	IdeviceFfiError *err = rsd_get_uuid(handshake, &uuid);
	if (err) {
		replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
		return;
	}

	NSString *uuidStr = uuid ? @(uuid) : nil;
	if (uuid) {
		rsd_free_string(uuid);
	}

	replyHandler(uuidStr, nil);
}

- (void)rsd_get_servicesWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
	int handleId = [body[@"handle"] intValue];
	if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != rsd_handshake_free) {
		replyHandler(nil, @"Invalid RSD handshake handle");
		return;
	}
	RsdHandshakeHandle *handshake = handles[@(handleId)].handle;

	CRsdServiceArray *services = NULL;
	IdeviceFfiError *err = rsd_get_services(handshake, &services);
	if (err) {
		replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
		return;
	}

	NSMutableArray *ans = [[NSMutableArray alloc] init];
	if (services && services->services) {
		for (size_t i = 0; i < services->count; ++i) {
			[ans addObject:RsdServiceToDictionary(&services->services[i])];
		}
	}

	if (services) {
		rsd_free_services(services);
	}
	replyHandler(ans, nil);
}

- (void)rsd_service_availableWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
	int handleId = [body[@"handle"] intValue];
	if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != rsd_handshake_free) {
		replyHandler(nil, @"Invalid RSD handshake handle");
		return;
	}
	RsdHandshakeHandle *handshake = handles[@(handleId)].handle;

	NSString *serviceName = body[@"service_name"];
	if (![serviceName isKindOfClass:NSString.class]) {
		replyHandler(nil, @"Invalid service name");
		return;
	}

	bool available = false;
	IdeviceFfiError *err = rsd_service_available(handshake, [serviceName UTF8String], &available);
	if (err) {
		replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
		return;
	}

	replyHandler(@(available), nil);
}

- (void)rsd_get_service_infoWithBody:(NSDictionary *)body replyHandler:(nonnull void (^)(id _Nullable, NSString * _Nullable))replyHandler {
	int handleId = [body[@"handle"] intValue];
	if (!handles[@(handleId)] || handles[@(handleId)].freeFunc != rsd_handshake_free) {
		replyHandler(nil, @"Invalid RSD handshake handle");
		return;
	}
	RsdHandshakeHandle *handshake = handles[@(handleId)].handle;

	NSString *serviceName = body[@"service_name"];
	if (![serviceName isKindOfClass:NSString.class]) {
		replyHandler(nil, @"Invalid service name");
		return;
	}

	CRsdService *serviceInfo = NULL;
	IdeviceFfiError *err = rsd_get_service_info(handshake, [serviceName UTF8String], &serviceInfo);
	if (err) {
		replyHandler(nil, [self errFreeFromIdeviceFfiError:err]);
		return;
	}

	NSDictionary *ans = RsdServiceToDictionary(serviceInfo);
	if (serviceInfo) {
		rsd_free_service(serviceInfo);
	}

	replyHandler(ans, nil);
}

@end
