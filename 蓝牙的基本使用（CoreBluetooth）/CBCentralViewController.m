//
//  CBCentralViewController.m
//  蓝牙的基本使用（CoreBluetooth）
//
//  Created by wangjianwei on 16/1/6.
//  Copyright © 2016年 JW. All rights reserved.
//  1.目前只实现了单连，没有实现多连
//  2.数据传输的速度比较慢：用图片数据传输测试，发现居然要30多分钟，传输速率平均 大概5kb/s
//  3.when PeripheralManager stopAdvertising, the CentralManager can not get a notify.
//  4.当PeripheralMangager 更改了内容时候，没有实时更新到CentralManager-----已经实现，通过添加定时器，重新扫描实现
//  5.后台发布数据已经实现，但是后台接受数据还是不行
#import "CBCentralViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#ifdef  DEBUG
#define JWLog(xx, ...)  NSLog(@"%s(%d): " xx, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define JWLog(xx, ...)
#endif
NSString * const kCharacteristicUUIDString = @"DBC38D1B-B755-442D-B3D4-F173C2F6DECB";
NSString * const kServiceUUIDString  = @"12AD7375-634D-4F66-9CD8-1D3D8C5B6006";
@interface CBCentralViewController ()<UINavigationControllerDelegate,UIImagePickerControllerDelegate,CBCentralManagerDelegate,CBPeripheralDelegate>

@property (weak, nonatomic) IBOutlet UITextView *bluetoothListTextView;
@property (weak, nonatomic) IBOutlet UITextView *transferContentTextView;
@property (weak, nonatomic) IBOutlet UILabel *transferSpeedLabel;
@property (weak, nonatomic) IBOutlet UISwitch *scanSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *setNotisfy;

@property (strong,nonatomic) CBCentralManager *centralManager;
/**用来保存我们扫描得到的蓝牙Peripherl*/
@property (strong,nonatomic)NSMutableArray *periphralsM;
/**用来保存接收到的数据*/
@property (strong,nonatomic)NSMutableData *dataToRecv;
/**用来保存将要发送的数据*/
@property (strong,nonatomic)NSMutableData *dataToWrite;
/**用来记录上一次数据传输的时间*/
@property (strong,nonatomic)NSDate *beginDate;

@end

@implementation CBCentralViewController

#pragma mark - lazy load
-(NSMutableArray *)periphralsM{
    if (_periphralsM == nil) {
        _periphralsM = [[NSMutableArray alloc]init];
    }
    return _periphralsM;
}
-(NSMutableData *)dataToRecv{
    if (_dataToRecv == nil) {
        _dataToRecv = [[NSMutableData alloc]init];
    }
    return _dataToRecv;
}
-(NSMutableData *)dataToWrite{
    if (_dataToWrite == nil) {
        _dataToWrite = [NSMutableData dataWithData:[@"456" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return _dataToWrite;
}
#pragma mark - View LifeCycle
- (void)viewDidLoad {
    [super viewDidLoad];

    //    NSDictionary *options = @{CBCentralManagerOptionRestoreIdentifierKey:@"JWCentralMangerIdentifier"};
    
    //初始化完成后，将会调用delegate 方法 centralManagerDidUpdatqeState：方法
    _centralManager = [[CBCentralManager alloc]initWithDelegate:self queue:nil options:nil];
    
    //定义一个重新开启扫描的timer 来保证同步，时间的选择应该根据实际需要来选择
    NSTimer *timer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(rescan) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop]addTimer:timer forMode:NSRunLoopCommonModes];
}

-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [self cleanup];
}
#pragma mark - action method
- (IBAction)scan:(UISwitch *)sender {
    if (sender.isOn) {
        //scan 之后将会调用centralManager:didDiscoverPeripheral:advertisementData:RSSI:method
        [self.centralManager scanForPeripheralsWithServices:nil options:nil];
    }else {
        [self.centralManager stopScan];
        [self cleanup];
    }
}
- (IBAction)setNotisfy:(id)sender {
    [self rescan];
}

-(void)cleanup{
    self.bluetoothListTextView.text = nil;
    self.transferContentTextView.text = nil;
    self.transferSpeedLabel.text = nil;
    
    [self.periphralsM enumerateObjectsUsingBlock:^(CBPeripheral* peripheral, NSUInteger idx, BOOL *  stop) {
        JWLog(@"%lu",(unsigned long)idx);
        
        for (CBService *service in peripheral.services) {
            for (CBCharacteristic* characteristic in service.characteristics) {
                if (characteristic.isNotifying) {
                    
                    //调用该方法之后将会触发-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error方法
                    JWLog(@"set notifycation no:for Characteristic:%@",characteristic);
                    [peripheral setNotifyValue:NO forCharacteristic:characteristic];
                }
            }
        }
        
        //该方法将会触发-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error方法
        JWLog(@"peripheral:%@ 断开了连接",peripheral.name);
        [self.centralManager cancelPeripheralConnection:peripheral];
    }];
    
    //以下这句话将会导致不会触发-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error，以及-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error方法因为peripheral已经消失了，所以也就不可能调用他的delegate方法,所以我在上面手动添加了打印信息
    [self.periphralsM removeAllObjects];
    [self.dataToRecv setLength:0];
}
-(void)rescan{
    if (self.scanSwitch.isOn) {
        //关了之后重新扫描就可以重新连接传输数据，不重启实测不能实现Peripheral 和 central 数据的一致性
        [self.centralManager stopScan];
        [self.centralManager scanForPeripheralsWithServices:nil options:nil];
    }
}
#pragma mark - CBCentralManager Delegate 
//如果添加了支持state preversation and restoration ，将会在重新启动后首先调用以下方法，如果没有支持，将会调用didUpdateState:方法
//-(void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary<NSString *,id> *)dict{
//    NSArray * peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey];
//    [peripherals enumerateObjectsUsingBlock:^(id  _Nonnull peripheral, NSUInteger idx, BOOL * _Nonnull stop) {
//        if (![self.periphralsM containsObject:peripheral]) {
//            [self.periphralsM addObject:peripheral];
//            [central connectPeripheral:peripheral options:nil];
//        }
//    }];
//    
//}
/**
 *  
 state:
 typedef NS_ENUM(NSInteger, CBCentralManagerState) {
	CBCentralManagerStateUnknown = 0,
	CBCentralManagerStateResetting,
	CBCentralManagerStateUnsupported,
	CBCentralManagerStateUnauthorized,
	CBCentralManagerStatePoweredOff,
	CBCentralManagerStatePoweredOn,
 };
 *
 */
-(void)centralManagerDidUpdateState:(CBCentralManager *)central{
    if (central.state != CBCentralManagerStatePoweredOn) {
        JWLog(@"当前蓝牙非就绪状态，可能没打开，可能不支持，可以根据具体的状态显示具体的原因");
        return;
    }
   
    JWLog(@"主人，可以进行蓝牙扫描了...");
    //可以在这里扫描，但是我们有个开关，所以就把扫描语句放在scan方法中了
    //scan 之后将会调用centralManager:didDiscoverPeripheral:advertisementData:RSSI:method
//    [self.centralManager scanForPeripheralsWithServices:nil options:nil];

}

-(void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI{
    //可以对RSSI进行相关的处理...如用来测距离，可以选择某些太远距离的蓝牙不予连接等等
    //RSSI 是信号强度
    JWLog(@"RSSI-%ld",(long)RSSI.integerValue);
    
    /**
     *  详细分析advertisementData
     * peripheral.name 是只读的，一般指设备的名称，就是你对自己的iPhone 叫啥名字
     * 我们修改的是LocalName，这个是可以修改的。从设备在advtertising的时候会传入一个字典，在其中可以指定名称。其实这个名称就是
     * 别人搜到的我们的蓝牙设备名称。反正安卓搜我们的peripheral 是可以显示这个localName的。但是名字的长度是受限制的
     */
    JWLog(@"peripheral:%@",peripheral.name);
    JWLog(@"advertisementData:%@--%lu",advertisementData,sizeof(advertisementData));
    NSString*localName = advertisementData[@"kCBAdvDataLocalName"];
    BOOL connectable = [advertisementData[@"kCBAdvDataConnectable"] boolValue];
    NSArray*serviceUUIDs = advertisementData[@"kCBAdvDataServiceUUIDs"];
    JWLog(@"%lu-%lu-%lu",sizeof(localName),sizeof(connectable),sizeof(serviceUUIDs));
    
   
    if (![self.periphralsM containsObject:peripheral]) {
        peripheral.delegate = self;
        
        //必须保存起来哦，不保存，那么就是局部变量，函数执行完毕就消失了，那么也不会调用他的代理方法，因为他都消失了，还怎么找得到他的代理是谁呢
        [self.periphralsM addObject:peripheral];
        
        //显示到蓝牙列表中，应该用tableView的，懒得用，这里的蓝牙名字如果有在localName中指定了，那么使用这个Peripheral 作为名字，否则，使用Peripheral.name 这个属性，一般这个属性是设备的名字
        NSString *bluetooth = localName? localName:peripheral.name;
        if (self.bluetoothListTextView.text) {
            self.bluetoothListTextView.text = [self.bluetoothListTextView.text stringByAppendingString:[NSString stringWithFormat:@"%@\n",bluetooth]];
        }else{
            self.bluetoothListTextView.text = bluetooth;
        }
    }
    
    //发现我们感兴趣的peripheral 我们可以进行连接，在调用完该方法之后，将会调用centralManger:didConnectPeripheral:
    //实际中，我们可以再此处进行筛选
    [central connectPeripheral:peripheral
                       options:nil];
    

}
-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral{
    JWLog(@"Periphral:%@ connected",peripheral.name);
    
    //1. 当我们发现我们需要的peripheral 我们可以停止扫描
    //    [central stopScan];
    //    JWLog(@"Scanning stoped");

    
    //连接完毕，我们用外设扫描它的服务,当发现服务的时候，会调用peripheral:didDiscoverServices:error:
    [peripheral discoverServices:nil];
    
}
// cancelPeripheralConnection:发起后将会调用该方法
-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error{
    
    JWLog(@"peripheral:%@ 断开了连接",peripheral.name);
    //2. 断开连接后，我们可以重新开启扫描
    //    [central scanForPeripheralsWithServices:nil options:nil];
    
    //以上1.2.如果执行，那么将会不停的扫描，连接、传输数据，我们选用了另一种用NSTimer 的方式进行控制，更加节约资源
}
#pragma mark - CBPeriphralDelegate
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error{
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
        return;
    }
    
    for (CBService *service in peripheral.services) {
        JWLog(@"Discovered service: %@",service);
        
        //找到service 之后我们去查找Characteristic，该方法将会触发peripheral:didDiscoverCharacteristicsForService:error:
        if ([service.UUID.UUIDString isEqualToString:kServiceUUIDString]) {
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error{
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
        return;
    }
    
    for (CBCharacteristic *characteristic in service.characteristics) {
        JWLog(@"Discovered characteristic: %@--%u",characteristic,characteristic.value.length);
        if ([characteristic.UUID.UUIDString isEqualToString:kCharacteristicUUIDString]) {
            
            //读取characteristic 数据
            //判断是否允许读
            if (characteristic.properties & CBCharacteristicPropertyRead) {
                
                if (self.setNotisfy.isOn) {
                    //清空数据
                    [self.dataToRecv setLength:0];
                    //Subscribing to a Characteristic's value 设立观察者，跟踪变化。
                    //失败将会调用peripheral:didUpdateNotificationStateForCharacteristic:error:，成功将会调用peripheral:didUpdateValueForCharacteristic:error:
                    [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                }else{
                    //该方法之后将会调用peripheral:didUpdateValueForCharacteristic:error:
                    //该方法只是一次读取，不能跟踪characteristic 的value的变化，而且数据量不应该太大,central 每次接受的数据有限制的
                    [peripheral readValueForCharacteristic:characteristic];

                }
                
            }else JWLog(@"不可读");
            
            //writing the value of a Characteristic 写数据到Characteristic
//            if(characteristic.properties & CBCharacteristicPropertyWrite){
//                
//                //如果写请求有问题将会调用 peripheral:didWriteValueForCharacteristic:error 进行反馈
//                [peripheral writeValue:self.dataToWrite forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
//            }else JWLog(@"不可写");
        }
    }
}
-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{ 
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
        return;
    }
    
    //characteristic.value 中包含peripheral传输过来的数据
    NSData *data = characteristic.value;
    //parse the data as needed 解析数据
    
    NSString *string = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    
    //在setNotifisfy 时候调用以下代码
    if(characteristic.isNotifying){
        //@"EOM"是我们自己约定的传输数据结尾表示结束的字符串
        if ([string isEqualToString:@"EOM"]){
            //这是为了当Peripheral数据更新的时候，我们仍然能够扫描到他们，并且重新建立连接，从而达到同步更新的目的
            [peripheral setNotifyValue:NO forCharacteristic:characteristic];
            [self.centralManager cancelPeripheralConnection:peripheral];
            JWLog(@"数据接收成功，断开连接");
        }
        //解析数据
        [self parseData:data];
    }else{
        
        //在readValue时候使用以下代码
        self.transferContentTextView.text = string;
        JWLog(@"RecvData:%@，总长度：%d",self.transferContentTextView.text,string.length);

    }
}
-(void)parseData:(NSData*)data{
    NSString *string = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    if ([string isEqualToString:@"EOM"]) {
        //所有数据接收完毕，显示数据
        self.transferContentTextView.text = [[NSString alloc]initWithData:self.dataToRecv encoding:NSUTF8StringEncoding];
        JWLog(@"RecvData:%@，总长度：%d",self.transferContentTextView.text,self.dataToRecv.length);
    }
    else{
        //数据没有接受完全，拼接到缓存尾部
        [self.dataToRecv appendData:data];
        
        //显示数据的传输速度
        [self showSpeed:data];
    }
}

//显示数据的传输速度
-(void)showSpeed:(NSData*)data{
    
    NSString *string = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    
   
    if (self.beginDate == nil) { //表示数据是第一次接受
        self.beginDate = [NSDate date];
        JWLog(@"recv data:长度：%d--内容:%@",string.length,string);
    }else{//数据不是第一次接受
        
        //获取当前的传输时间
        NSDate* endDate = [NSDate date];
        
        //此时的self.beginDate 一定是有数据的，且记录了上次传输完成的时间
        NSTimeInterval t = [endDate timeIntervalSinceDate:self.beginDate]; //单位是s
        CGFloat kbCount = data.length/1024.0; //单位是KB
        CGFloat speed = kbCount/t; //单位是KB/S
        if (speed != NAN) { //NAN 表示数据缺失，或者无穷大
            self.transferSpeedLabel.text = [NSString stringWithFormat:@"%.02f kb/s ",speed];
        }else{
            //speed 计算错误的时候，我就不显示了，让用看到不知道啥意思
            self.transferSpeedLabel.text = nil;
        }
        //记录上一次的传输时间
        self.beginDate = endDate;
        JWLog(@"recv data:长度：%d--内容:%@--速度： %.02f kb/s",string.length,string,speed);
    }
}
#pragma mark 错误回调
-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
        return;
    }
    if(characteristic.isNotifying) JWLog(@"set notification  Yes");
    else {
        JWLog(@"set notification  NO");
    };
}
-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    if (error) {
        JWLog(@"%@",[error localizedDescription]);
        return;
    }else{
        
        JWLog(@"write value success...");
    }
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
@end
