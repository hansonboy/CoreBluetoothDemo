//
//  CBPeriphralViewController.m
//  蓝牙的基本使用（CoreBluetooth）
//
//  Created by wangjianwei on 16/1/6.
//  Copyright © 2016年 JW. All rights reserved.
//

#import "CBPeriphralViewController.h"
#import "UIImage+FixOrientation.h"
#import <CoreBluetooth/CoreBluetooth.h>
#define kiOS8Older  ([UIDevice currentDevice].systemVersion.floatValue >= 8.0)
#ifdef  DEBUG
#define JWLog(xx, ...)  NSLog(@"%s(%d): " xx, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define JWLog(xx, ...)
#endif
#define kMTU 155
@interface CBPeriphralViewController ()<UINavigationControllerDelegate,UIImagePickerControllerDelegate,CBPeripheralManagerDelegate,UITextViewDelegate>
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UISwitch *startAdvertisingSwitch;
@property (weak, nonatomic) IBOutlet UITextView *responseTextView;

@property (strong,nonatomic)CBPeripheralManager *peripheralManager;
@property (strong,nonatomic)CBMutableCharacteristic *characteristic;
@property (strong,nonatomic)CBMutableService *service;

/**记录将要发送的数据*/
@property (strong,nonatomic)NSData *updatedData;

/**用来记录下一次应该发送的数据的位置，因为数据太大的时候，不能够一次发完*/
@property (assign,nonatomic)NSUInteger sendIndex;
@end

@implementation CBPeriphralViewController
#pragma mark lazyload
-(CBMutableCharacteristic *)characteristic{
    if (_characteristic == nil) {
        /**
         type: UUID
         properties：属性设置 根据需要设置
         permission: 权限设置  根据需要设置
         */
        _characteristic = [[CBMutableCharacteristic alloc]initWithType:[CBUUID UUIDWithString:kCharacteristicUUIDString] properties:CBCharacteristicPropertyRead|CBCharacteristicPropertyNotify|CBCharacteristicPropertyWrite value:nil permissions:CBAttributePermissionsReadable|CBAttributePermissionsWriteable];
    }
    return _characteristic;
}
-(CBMutableService *)service{
    if (_service == nil) {
        _service = [[CBMutableService alloc]initWithType:[CBUUID UUIDWithString:kServiceUUIDString] primary:YES];
        //这里必须设置characteristic 属性
        _service.characteristics = @[self.characteristic];
    }
    return _service;
}
-(NSData *)updatedData{
    //传输什么样的数据，可以在这里改哦，不一定非得用textView.text的
    NSString *updateStr = self.textView.text;
    _updatedData = [updateStr dataUsingEncoding:NSUTF8StringEncoding];
    JWLog(@"updateData length:%lu",(unsigned long)_updatedData.length);
    return _updatedData;
}
#pragma mark View LifeCycle
- (void)viewDidLoad {
    [super viewDidLoad];
//    NSDictionary *options = @"CBPeripheralManagerOptionRestoreIdentifierKey:JWPeripheralManager"};
    //1.该方法之后将会调用peripheralManagerDidUpdateState:
    _peripheralManager = [[CBPeripheralManager alloc]initWithDelegate:self queue:nil options:nil];
}
#pragma mark - action
- (IBAction)advertising:(UISwitch*)sender {
    if (sender.isOn) {
        //之后将会调用peripheralManagerDidStartAdvertising:error:
        //注意advertisement 的28 bytes字节限制，（不包含2bytes 的头信息）+10bytes(只限于CBAdvertisementDataLocalNameKey字段),这里我也不太清楚，实践发现名字长度设置太长会自动截断，如我下面就设置的很长，以下名称ChanceappIdChanceappIdChanceappIdChanceappId修改只得到了ChanceappIdChanceappIdChancea ，如果加上后面的\0，是30个字节
        
        [self.peripheralManager startAdvertising:@{CBAdvertisementDataServiceUUIDsKey:@[self.characteristic.UUID], CBAdvertisementDataLocalNameKey:@"王建伟"}];
    }else [self.peripheralManager stopAdvertising];
}

#pragma mark - CBPeripheralManager Delegate
//以下方法是为了restore state
//-(void)peripheralManager:(CBPeripheralManager *)peripheral willRestoreState:(NSDictionary<NSString *,id> *)dict{
//    [self.peripheralManager startAdvertising:dict];
//}
-(void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral{
    
    /**
     *  
     typedef NS_ENUM(NSInteger, CBPeripheralManagerState) {
     CBPeripheralManagerStateUnknown = 0,
     CBPeripheralManagerStateResetting,
     CBPeripheralManagerStateUnsupported,
     CBPeripheralManagerStateUnauthorized,
     CBPeripheralManagerStatePoweredOff,
     CBPeripheralManagerStatePoweredOn,
     } NS_ENUM_AVAILABLE(NA, 6_0);
     */
    if (peripheral.state != CBPeripheralManagerStatePoweredOn) {
        JWLog(@"蓝牙状态非就绪...");
    }
    JWLog(@"CBPeripheral state Power On...");
    
    /**
     *  publish your services and Characteristics 发布自己的services 和 Characteristics. 之后将会调用peripheralManager:didAddService:error:方法
     */
    [peripheral addService:self.service];
    
}

//每次调用该方法都需要显示的调用[peripheral respondToRequest:withResult:]方法
-(void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request{
    if ([request.characteristic.UUID isEqual:self.characteristic.UUID]) {
        JWLog(@"recieve read request :%@...",request);
        
        self.characteristic.value = [@"you are success... 成功了！！！" dataUsingEncoding:NSUTF8StringEncoding];
        
//        JWLog(@"offset:%d",request.offset);
        //以下是进行错误处理，条件筛选
        if (request.offset > self.characteristic.value.length) {
            [peripheral respondToRequest:request withResult:CBATTErrorInvalidOffset];
            JWLog(@"CBATTErrorInvalidOffset---%d",request.offset);
            return;
        }
        if (!(self.characteristic.properties & CBCharacteristicPropertyRead)) {
            [peripheral respondToRequest:request withResult:CBATTErrorReadNotPermitted];
            return;
        }
       
        
        //此处设置request.value 就会将数据传输给 Central
        request.value = [self.characteristic.value subdataWithRange:NSMakeRange(request.offset, self.characteristic.value.length - request.offset)];
        //这句话一定要显示调用一次
        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
        JWLog(@"respondToReadRequest:success.");
    }
}

-(void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray *)requests{
     JWLog(@"recieve write request...");
    CBATTRequest *request = requests[0];
    if ([request.characteristic.UUID isEqual:self.characteristic.UUID]) {
        
        if (!(self.characteristic.properties & CBCharacteristicPropertyWrite)) {
            [peripheral respondToRequest:request withResult:CBATTErrorWriteNotPermitted];
            return;
        }
        //request.value中包含central 发过来想要写入的数据
        self.characteristic.value = request.value;
        
        //虽然有很多的写请求，但是把他们看成一个整体，所以只对第一个请求执行respondToRequest:withResult方法
        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
         JWLog(@"respondToWriteRequest:success.---%@",[[NSString alloc]initWithData:request.value encoding:NSUTF8StringEncoding]);
        
        JWLog(@"------------%@-------------------",[[NSString alloc] initWithData:request.value encoding:NSUTF8StringEncoding]);
        self.responseTextView.text = [[NSString alloc] initWithData:request.value encoding:NSUTF8StringEncoding];
    }
}

//当Central 订阅了Characteristic 时候，我们调用该方法
-(void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic{
    //central.maximumUpdateValueLength 字段就是以后kMTU 大小，以后发送数据包不得超过
    JWLog(@"didSubscribeToCharacteristic ...central:%d",central.maximumUpdateValueLength);
    
    //初始化要发送的数据位置
    self.sendIndex  = 0;
    if (self.updatedData) {
        [self sendData:self.updatedData];
    }
}
//当 Central 端执行 peripheral：setNotisfy:forCharacteristic:方法 取消订阅的时候，将会调用该方法
-(void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic{
    JWLog(@"取消订阅了");
}

-(void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral{
  //继续发送数据
    JWLog(@"继续发送数据");
    [self sendData:self.updatedData];
}
-(void)sendData:(NSData*)data{
    
    while (1) {
        //发送完毕，尾部添加@“EOM”
        if (self.sendIndex >= data.length) {
           
            NSData *eomData =  [@"EOM" dataUsingEncoding:NSUTF8StringEncoding];
            BOOL didSend = [self.peripheralManager updateValue:eomData forCharacteristic:self.characteristic onSubscribedCentrals:nil];
            if (didSend) {
                JWLog(@"sent: EOM");
            }
            return;
        }
        //确定发送数据包的大小，不得超过kMTU
        NSUInteger sendCount = (data.length - self.sendIndex  > kMTU)?kMTU:data.length - self.sendIndex ;
        NSData *sendData = [data subdataWithRange:NSMakeRange(self.sendIndex, sendCount)];
        
        
        BOOL didSendValue = [self.peripheralManager updateValue:sendData forCharacteristic:self.characteristic onSubscribedCentrals:nil];
        if (didSendValue) {
            self.sendIndex += sendCount;
//            JWLog(@"data:%d---index:%d---sendCount:%d",data.length,self.sendIndex,sendCount);
        }
        else{
            //如果不成功，表示当前线程正在发送数据，被占用了，资源可用的时候，将会调用peripheralManagerIsReadyUpdateSubcribers
            JWLog(@"发送失败");
            return;
        }
    }
}
#pragma mark 状态监测错误回调
-(void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(CBService *)service error:(NSError *)error{
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
    }else{
        JWLog(@"添加服务成功：%@",service);
    }
}
-(void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error{
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
    }else{
        JWLog(@"开始广播...");
    }
}
//触摸屏幕的时候让键盘消失掉的一种简单方式
-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event{
    [self.textView resignFirstResponder];
}
#pragma mark - UITextViewDelegate
-(void)textViewDidEndEditing:(UITextView *)textView{
    if (self.startAdvertisingSwitch.isOn) {
        self.startAdvertisingSwitch.on = NO;
        [self.peripheralManager stopAdvertising];
    }
    [textView resignFirstResponder];
}
@end
