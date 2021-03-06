//
//  HCKScanController.m
//  HCKEddStone
//
//  Created by aa on 2017/11/28.
//  Copyright © 2017年 HCK. All rights reserved.
//

#import "HCKScanController.h"
#import "HCKBaseTableView.h"
#import "HCKScanBeaconModel.h"
#import "HCKEddStoneUIDCell.h"
#import "HCKEddStoneURLCell.h"
#import "HCKEddStoneTLMCell.h"
#import "HCKScanInfoCell.h"
#import "HCKEddStoneiBeaconCell.h"
#import "HCKAboutController.h"
#import "HCKScanSearchView.h"
#import "HCKScanSearchButton.h"
#import "HCKMainTabBarController.h"
#import "MKBaseReceiveBeacon+HCKAdd.h"
#import "MKConnectDeviceProgressView.h"

static NSString *const HCKUIDDataKey = @"UID";
static NSString *const HCKURLDataKey = @"URL";
static NSString *const HCKTLMDataKey = @"TLM";
static NSString *const HCKIbeaconKey = @"iBeacon";
static NSString *const HCKPeripheralInfoKey = @"HCKPeripheralInfoKey";
static NSString *const HCKIdentifierKey = @"HCKIdentifierKey";
static NSString *const HCKLeftButtonAnimationKey = @"HCKLeftButtonAnimationKey";

static CGFloat const offset_X = 15.f;
static CGFloat const searchButtonHeight = 40.f;
static CGFloat const headerViewHeight = 90.f;
static CGFloat const uidCellHeight = 70.f;
static CGFloat const urlCellHeight = 55.f;
static CGFloat const tlmCellHeight = 110.f;

static NSTimeInterval const kRefreshInterval = .5f;

@interface HCKSortModel : NSObject

/**
 过滤条件，mac或者名字包含的搜索条件
 */
@property (nonatomic, copy)NSString *searchName;

/**
 过滤设备的rssi
 */
@property (nonatomic, assign)NSInteger sortRssi;

/**
 是否打开了搜索条件
 */
@property (nonatomic, assign)BOOL isOpen;

@end

@implementation HCKSortModel

@end

@interface HCKScanController ()<UITableViewDelegate, UITableViewDataSource, MKEddystoneScanDelegate>

@property (nonatomic, strong)HCKScanSearchButton *searchButton;

@property (nonatomic, strong)UIImageView *circleIcon;

@property (nonatomic, strong)HCKBaseTableView *tableView;

/**
 数据源
 */
@property (nonatomic, strong)NSMutableArray *dataList;


@property (nonatomic, strong)HCKSortModel *sortModel;

@property (nonatomic, strong)UITextField *passwordField;

/**
 当从配置页面返回的时候，需要扫描
 */
@property (nonatomic, assign)BOOL needScan;

@property (nonatomic, strong)dispatch_source_t scanTimer;

/**
 缓存用户输入的密码。只有连接成功设备之后才会缓存
 */
@property (nonatomic, copy)NSString *localPassword;

@property (nonatomic, assign)CFRunLoopObserverRef observerRef;

@property (nonatomic, assign)BOOL isNeedRefresh;

@end

@implementation HCKScanController

#pragma mark - life circle
- (void)dealloc{
    NSLog(@"HCKScanController销毁");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:HCKCentralDeallocNotification object:nil];
    //移除runloop的监听
    CFRunLoopRemoveObserver(CFRunLoopGetCurrent(), self.observerRef, kCFRunLoopCommonModes);
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    if (self.needScan && [MKCentralManager sharedInstance].managerState == MKEddystoneCentralManagerStateEnable) {
        self.needScan = NO;
        self.leftButton.selected = NO;
        [self leftButtonMethod];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadSubViews];
    [self runloopObserver];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(setCentralScanDelegate)
                                                 name:HCKCentralDeallocNotification
                                               object:nil];
    [self setCentralScanDelegate];
    [self performSelector:@selector(showCentralStatus) withObject:nil afterDelay:0.5];
    // Do any additional setup after loading the view.
}

#pragma mark - 父类方法

- (void)leftButtonMethod{
    if ([MKCentralManager sharedInstance].managerState != MKEddystoneCentralManagerStateEnable) {
        [self.view showCentralToast:@"The current system of bluetooth is not available!"];
        return;
    }
    self.leftButton.selected = !self.leftButton.selected;
    if (!self.leftButton.isSelected) {
        //停止扫描
        [self.circleIcon.layer removeAnimationForKey:HCKLeftButtonAnimationKey];
        [[MKCentralManager sharedInstance] stopScanPeripheral];
        if (self.scanTimer) {
            dispatch_cancel(self.scanTimer);
        }
        return;
    }
    [self.dataList removeAllObjects];
    [self.tableView reloadData];
    //刷新顶部设备数量
    [self resetDevicesNum];
    [self addAnimationForLeftButton];
    [self scanTimerRun];
}

- (void)rightButtonMethod{
    HCKAboutController *vc = [[HCKAboutController alloc] initWithNavigationType:GYNaviTypeShow];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 代理方法

#pragma mark - UITableViewDataSource
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    @synchronized(self.dataList) {
        return self.dataList.count;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    @synchronized(self.dataList){
        if (section < self.dataList.count) {
            HCKScanBeaconModel *model = self.dataList[section];
            @synchronized(model.dataArray){
                return (model.dataArray.count + 1);
            }
        }
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    if (indexPath.row == 0) {
        //第一个row固定为设备信息帧
        @synchronized(self.dataList){
            HCKScanInfoCell *cell = [HCKScanInfoCell initCellWithTableView:tableView];
            cell.beacon = self.dataList[indexPath.section];
            WS(weakSelf);
            cell.connectPeripheralBlock = ^(NSInteger section) {
                [weakSelf showPasswordAlert:section];
            };
            return cell;
        };
    }
    HCKScanBaseCell *cell = [self loadCellDataWithIndexPath:indexPath];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    if (indexPath.row == 0) {
        return headerViewHeight;
    }
    if (indexPath.section < self.dataList.count) {
        @synchronized(self.dataList){
            HCKScanBeaconModel *model = self.dataList[indexPath.section];
            @synchronized(model.dataArray){
                MKBaseReceiveBeacon *beacon = model.dataArray[indexPath.row - 1];
                switch (beacon.frameType) {
                    case MKEddystoneUIDFrameType:
                        return uidCellHeight;
                        
                    case MKEddystoneURLFrameType:
                        return urlCellHeight;
                        
                    case MKEddystoneTLMFrameType:
                        return tlmCellHeight;
                        
                    case MKEddystoneiBeaconFrameType:
                        return [self getiBeaconCellHeightWithBeacon:beacon];
                    default:
                        break;
                }
            }
        }
    }
    return 0.f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section{
    return 5.f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section{
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kScreenWidth, 5.f)];
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section{
    return 5.f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section{
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kScreenWidth, 5.f)];
    return view;
}

#pragma mark - MKEddystoneScanDelegate
- (void)didReceiveBeacon:(MKBaseReceiveBeacon *)beacon manager:(MKCentralManager *)manager{
    [self updateDataWithBeacon:beacon];
}

- (void)centralManagerStopScan:(MKCentralManager *)manager{
    //如果是左上角在动画，则停止动画
    if (self.leftButton.isSelected) {
        [self.circleIcon.layer removeAnimationForKey:HCKLeftButtonAnimationKey];
        [self.leftButton setSelected:NO];
    }
}

- (void)centralManagerStartScan:(MKCentralManager *)manager{
    
}

#pragma mark - notice method
- (void)setCentralScanDelegate{
    [MKCentralManager sharedInstance].scanDelegate = self;
}

#pragma mark - Private method

- (void)showCentralStatus{
    if (kSystemVersion >= 11.0 && [MKCentralManager sharedInstance].managerState != MKEddystoneCentralManagerStateEnable) {
        //对于iOS11以上的系统，打开app的时候，如果蓝牙未打开，弹窗提示，后面系统蓝牙状态再发生改变就不需要弹窗了
        NSString *msg = @"The current system of bluetooth is not available!";
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Dismiss"
                                                                                 message:msg
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *moreAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:moreAction];
        
        [kAppRootController presentViewController:alertController animated:YES completion:nil];
        return;
    }
    [self leftButtonMethod];
}

#pragma mark - 扫描部分
/**
 搜索设备
 */
- (void)serachButtonPressed{
    HCKScanSearchView *searchView = [[HCKScanSearchView alloc] init];
    WS(weakSelf);
    searchView.scanSearchViewDismisBlock = ^(BOOL update, NSString *text, CGFloat rssi) {
        if (!update) {
            return ;
        }
        weakSelf.sortModel.sortRssi = (NSInteger)rssi;
        weakSelf.sortModel.searchName = text;
        weakSelf.sortModel.isOpen = YES;
        weakSelf.searchButton.searchConditions = (ValidStr(weakSelf.sortModel.searchName) ?
  [@[weakSelf.sortModel.searchName,[NSString stringWithFormat:@"%@dBm",stringFromInteger(weakSelf.sortModel.sortRssi)]] mutableCopy] :
  [@[[NSString stringWithFormat:@"%@dBm",stringFromInteger(weakSelf.sortModel.sortRssi)]] mutableCopy]);
        weakSelf.leftButton.selected = NO;
        [weakSelf leftButtonMethod];
    };
    [searchView showWithText:(self.sortModel.isOpen ? self.sortModel.searchName : @"")
                   rssiValue:(self.sortModel.isOpen ? stringFromInteger(self.sortModel.sortRssi) : @"")];
}

- (void)updateDataWithBeacon:(MKBaseReceiveBeacon *)beacon{
    if (!beacon || beacon.frameType == MKEddystoneUnknownFrameType || beacon.frameType == MKEddystoneNODATAFrameType) {
        return;
    }
    if (self.sortModel.isOpen) {
        if (!ValidStr(self.sortModel.searchName)) {
            //打开了过滤，但是只过滤rssi
            [self filterBeaconWithRssi:beacon];
            return;
        }
        //如果打开了过滤，先看是否需要过滤设备名字和mac地址
        //如果是设备信息帧,判断mac和名字是否符合要求
        [self filterBeaconWithSearchName:beacon];
        return;
    }
    [self processBeacon:beacon];
}

/**
 通过rssi过滤设备
 */
- (void)filterBeaconWithRssi:(MKBaseReceiveBeacon *)beacon{
    if ([beacon.rssi integerValue] < self.sortModel.sortRssi) {
        return;
    }
    [self processBeacon:beacon];
}

/**
 通过设备名称和mac地址过滤设备，这个时候肯定开启了rssi

 @param beacon 设备
 */
- (void)filterBeaconWithSearchName:(MKBaseReceiveBeacon *)beacon{
    if ([beacon.rssi integerValue] < self.sortModel.sortRssi) {
        return;
    }
    if (beacon.frameType == MKEddystoneInfoFrameType) {
        //如果是设备信息帧
        MKReceivePeripheralInfoBeacon *tempBeacon = (MKReceivePeripheralInfoBeacon *)beacon;
        if ([tempBeacon.peripheralName containsString:self.sortModel.searchName] || [tempBeacon.macAddress containsString:self.sortModel.searchName]) {
            //如果mac地址和设备名称包含搜索条件，则加入
            [self processBeacon:beacon];
        }
        return;
    }
    //如果不是设备信息帧，则判断对应的有没有设备信息帧在当前数据源，如果没有直接舍弃，如果存在，则加入
    NSString *identy = beacon.peripheral.identifier.UUIDString;
    @synchronized(self.dataList){
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"identifier == %@", identy];
        NSArray *array = [self.dataList filteredArrayUsingPredicate:predicate];
        BOOL contain = ValidArray(array);
        if (!contain) {
            return;
        }
        HCKScanBeaconModel *exsitModel = array[0];
        [self beaconExistDataSource:exsitModel beacon:beacon];
    }
}

- (void)processBeacon:(MKBaseReceiveBeacon *)beacon{
    //查看数据源中是否已经存在相关设备
    NSString *identy = beacon.peripheral.identifier.UUIDString;
    @synchronized(self.dataList){
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"identifier == %@", identy];
        NSArray *array = [self.dataList filteredArrayUsingPredicate:predicate];
        BOOL contain = ValidArray(array);
        if (contain) {
            //如果是已经存在了，如果是设备信息帧和TLM帧，直接替换，如果是URL、iBeacon、UID中的一种，则判断数据内容是否和已经存在的信息一致，如果一致，不处理，如果不一致，则直接加入到HCKScanBeaconModel的dataArray里面去
            HCKScanBeaconModel *exsitModel = array[0];
            [self beaconExistDataSource:exsitModel beacon:beacon];
            return;
        }
        //不存在，则加入
        [self beaconNoExistDataSource:beacon];
    }
}

/**
 将扫描到的设备加入到数据源

 @param beacon 扫描到的设备
 */
- (void)beaconNoExistDataSource:(MKBaseReceiveBeacon *)beacon{
    HCKScanBeaconModel *newModel = [[HCKScanBeaconModel alloc] init];
    [self.dataList addObject:newModel];
    newModel.index = self.dataList.count - 1;
    newModel.identifier = beacon.peripheral.identifier.UUIDString;
    newModel.rssi = beacon.rssi;
    if (beacon.frameType == MKEddystoneInfoFrameType) {
        //如果是设备信息帧
        newModel.infoBeacon = (MKReceivePeripheralInfoBeacon *)beacon;
        [self needRefreshList];
    }else{
        //如果是URL、TLM、UID、iBeacon中的一种，直接加入到newModel中的数据帧数组里面
        [newModel.dataArray addObject:beacon];
        beacon.index = 0;
        [self needRefreshList];
    }
}

/**
 如果是已经存在了，如果是设备信息帧和TLM帧，直接替换，如果是URL、iBeacon、UID中的一种，则判断数据内容是否和已经存在的信息一致，如果一致，不处理，如果不一致，则直接加入到HCKScanBeaconModel的dataArray里面去

 @param exsitModel 位于哪个HCKScanBeaconModel下面
 @param beacon  新扫描到的数据帧
 */
- (void)beaconExistDataSource:(HCKScanBeaconModel *)exsitModel beacon:(MKBaseReceiveBeacon *)beacon{
    if (beacon.frameType == MKEddystoneInfoFrameType) {
        //设备信息帧
        exsitModel.infoBeacon = (MKReceivePeripheralInfoBeacon *)beacon;
        [self needRefreshList];
        return;
    }
    //如果是URL、TLM、UID、iBeacon中的一种，
    //如果eddStone帧数组里面已经包含该类型数据，则判断是否是TLM，如果是TLM直接替换数组中的数据，如果不是，则判断广播内容是否一样，如果一样，则不处理，如果不一样，直接加入到帧数组
    for (MKBaseReceiveBeacon *model in exsitModel.dataArray) {
        if ([model.advertiseData isEqualToData:beacon.advertiseData]) {
            //如果广播内容一样，直接舍弃数据
            return;
        }
        if (model.frameType == beacon.frameType && beacon.frameType == MKEddystoneTLMFrameType) {
            //TLM信息帧需要替换
            beacon.index = model.index;
            [exsitModel.dataArray replaceObjectAtIndex:model.index withObject:beacon];
            [self needRefreshList];
            return;
        }
    }
    //如果eddStone帧数组里面不包含该数据，直接添加
    [exsitModel.dataArray addObject:beacon];
    beacon.index = exsitModel.dataArray.count - 1;
    NSArray *tempArray = [NSArray arrayWithArray:exsitModel.dataArray];
    NSArray *sortedArray = [tempArray sortedArrayUsingComparator:^NSComparisonResult(MKBaseReceiveBeacon *p1, MKBaseReceiveBeacon *p2){
        if (p1.frameType > p2.frameType) {
            return NSOrderedDescending;
        }else{
            return NSOrderedAscending;
        }
    }];
    [exsitModel.dataArray removeAllObjects];
    for (NSInteger i = 0; i < sortedArray.count; i ++) {
        MKBaseReceiveBeacon *tempModel = sortedArray[i];
        tempModel.index = i;
        [exsitModel.dataArray addObject:tempModel];
    }
    [self needRefreshList];
}

- (HCKScanBaseCell *)loadCellDataWithIndexPath:(NSIndexPath *)indexPath{
    @synchronized(self.dataList){
        if (!indexPath || indexPath.section >= self.dataList.count) {
            return nil;
        }
        HCKScanBeaconModel *model = self.dataList[indexPath.section];
        @synchronized(model.dataArray){
            MKBaseReceiveBeacon *beacon = model.dataArray[indexPath.row - 1];
            HCKScanBaseCell *cell;
            if (beacon.frameType == MKEddystoneUIDFrameType) {
                //UID
                cell = [HCKEddStoneUIDCell initCellWithTableView:self.tableView];
            }else if (beacon.frameType == MKEddystoneURLFrameType){
                //URL
                cell = [HCKEddStoneURLCell initCellWithTableView:self.tableView];
            }else if (beacon.frameType == MKEddystoneTLMFrameType){
                //TLM
                cell = [HCKEddStoneTLMCell initCellWithTableView:self.tableView];
            }else if (beacon.frameType == MKEddystoneiBeaconFrameType){
                cell = [HCKEddStoneiBeaconCell initCellWithTableView:self.tableView];
            }
            if ([cell respondsToSelector:@selector(setBeacon:)]) {
                [cell performSelector:@selector(setBeacon:) withObject:beacon];
            }
            return cell;
        }
    }
}

- (NSString *)getDataKeyWithFrameType:(MKFrameType )frameType{
    switch (frameType) {
        case MKEddystoneUIDFrameType:
            return HCKUIDDataKey;
          
        case MKEddystoneURLFrameType:
            return HCKURLDataKey;
        
        case MKEddystoneTLMFrameType:
            return HCKTLMDataKey;
            
        case MKEddystoneInfoFrameType:
            return HCKPeripheralInfoKey;
            
        case MKEddystoneUnknownFrameType:
            return @"";
            
        case MKEddystoneiBeaconFrameType:
            return HCKIbeaconKey;
        default:
            break;
    }
    return @"";
}

- (CGFloat )getiBeaconCellHeightWithBeacon:(MKBaseReceiveBeacon *)beacon{
    MKReceiveiBeacon *iBeaconModel = (MKReceiveiBeacon *)beacon;
    return [HCKEddStoneiBeaconCell getCellHeightWithUUID:iBeaconModel.uuid];
}

#pragma mark - 连接设备

- (void)connectPeripheral:(NSInteger )section{
    if (section >= self.dataList.count) {
        return;
    }
    HCKScanBeaconModel *model = self.dataList[section];
    if (!model) {
        return;
    }
    NSString *password = self.passwordField.text;
    if (!ValidStr(password) || password.length != 8) {
        [self.view showCentralToast:@"Password error"];
        return;
    }
    CBPeripheral *peripheral;
    if (model.infoBeacon) {
        peripheral = model.infoBeacon.peripheral;
    }else if (ValidArray(model.dataArray)){
        MKBaseReceiveBeacon *beacon = model.dataArray[0];
        peripheral = beacon.peripheral;
    }
    if (!self.leftButton.isSelected) {
        //停止扫描
        [self.circleIcon.layer removeAnimationForKey:HCKLeftButtonAnimationKey];
        [[MKCentralManager sharedInstance] stopScanPeripheral];
        if (self.scanTimer) {
            dispatch_cancel(self.scanTimer);
        }
    }
    MKConnectDeviceProgressView *progressView = [[MKConnectDeviceProgressView alloc] init];
    [progressView showConnectAlertViewWithTitle:@"Connecting..."];
    WS(weakSelf);
    [[MKCentralManager sharedInstance] connectPeripheral:peripheral password:password progressBlock:^(float progress) {
        [progressView setProgress:(progress * 0.01)];
    } sucBlock:^(CBPeripheral *peripheral) {
        [HCKDataManager share].password = password;
        weakSelf.localPassword = password;
        [progressView dismiss];
        HCKMainTabBarController *vc = [[HCKMainTabBarController alloc] init];
        NSDictionary *dic = @{
                              peripheralIdenty:peripheral,
                              passwordIdenty : [password copy]
                              };
        vc.params = dic;
        [weakSelf.navigationController pushViewController:vc animated:YES];
        weakSelf.needScan = YES;
    } failedBlock:^(NSError *error) {
        [HCKDataManager share].password = @"";
        [progressView dismiss];
        [weakSelf.view showCentralToast:error.userInfo[@"errorInfo"]];
        weakSelf.leftButton.selected = NO;
        [weakSelf leftButtonMethod];
    }];
}

- (void)showPasswordAlert:(NSInteger )section{
    NSString *msg = @"Please enter connection password.";
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Enter password"
                                                                             message:msg
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    WS(weakSelf);
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        weakSelf.passwordField = nil;
        weakSelf.passwordField = textField;
        if (ValidStr(weakSelf.localPassword)) {
            textField.text = weakSelf.localPassword;
        }
        weakSelf.passwordField.placeholder = @"8 characters";
        [textField addTarget:self action:@selector(passwordInput) forControlEvents:UIControlEventEditingChanged];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.leftButton.selected = NO;
        [weakSelf leftButtonMethod];
    }];
    [alertController addAction:cancelAction];
    UIAlertAction *moreAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf connectPeripheral:section];
    }];
    [alertController addAction:moreAction];
    
    [kAppRootController presentViewController:alertController animated:YES completion:nil];
}

/**
 监听输入的密码
 */
- (void)passwordInput{
    NSString *tempInputString = [self.passwordField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!ValidStr(tempInputString)) {
        self.passwordField.text = @"";
        return;
    }
    NSString *newInput = [tempInputString substringWithRange:NSMakeRange(tempInputString.length - 1, 1)];
    //只能是字母、数字
    BOOL correct = [newInput isLetterOrRealNumbers];
    NSString *sourceString = (correct ? tempInputString : [tempInputString substringWithRange:NSMakeRange(0, tempInputString.length - 1)]);
    self.passwordField.text = (sourceString.length > 8 ? [sourceString substringToIndex:8] : sourceString);
}

- (void)resetDevicesNum{
    [self.titleLabel setText:[NSString stringWithFormat:@"Devices(%@)",stringFromInteger(self.dataList.count)]];
}

- (void)addAnimationForLeftButton{
    [self.circleIcon.layer removeAnimationForKey:HCKLeftButtonAnimationKey];
    [self.circleIcon.layer addAnimation:[self animation] forKey:HCKLeftButtonAnimationKey];
}

- (CABasicAnimation *)animation{
    CABasicAnimation *transformAnima = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    transformAnima.duration = 2.f;
    transformAnima.fromValue = @(0);
    transformAnima.toValue = @(2 * M_PI);
    transformAnima.autoreverses = NO;
    transformAnima.repeatCount = MAXFLOAT;
    transformAnima.removedOnCompletion = NO;
    return transformAnima;
}

#pragma mark - 扫描监听
- (void)scanTimerRun{
    if (self.scanTimer) {
        dispatch_cancel(self.scanTimer);
    }
    [[MKCentralManager sharedInstance] startScanPeripheral];
    self.scanTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,dispatch_get_global_queue(0, 0));
    //开始时间
    dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC);
    //间隔时间
    uint64_t interval = 60 * NSEC_PER_SEC;
    dispatch_source_set_timer(self.scanTimer, start, interval, 0);
    dispatch_source_set_event_handler(self.scanTimer, ^{
        [[MKCentralManager sharedInstance] stopScanPeripheral];
    });
    dispatch_resume(self.scanTimer);
    
}

#pragma mark - 刷新
- (void)needRefreshList {
    //标记需要刷新
    self.isNeedRefresh = YES;
    //唤醒runloop
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (void)runloopObserver {
    WS(weakSelf);
    __block NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
    self.observerRef = CFRunLoopObserverCreateWithHandler(CFAllocatorGetDefault(), kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        if (activity == kCFRunLoopBeforeWaiting) {
            //runloop空闲的时候刷新需要处理的列表,但是需要控制刷新频率
            NSTimeInterval currentInterval = [[NSDate date] timeIntervalSince1970];
            if (currentInterval - timeInterval < kRefreshInterval) {
                return;;
            }
            timeInterval = currentInterval;
            if (weakSelf.isNeedRefresh) {
                [weakSelf.tableView reloadData];
                [weakSelf resetDevicesNum];
                weakSelf.isNeedRefresh = NO;
            }
        }
    });
    //添加监听，模式为kCFRunLoopCommonModes
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), self.observerRef, kCFRunLoopCommonModes);
}

- (void)loadSubViews{
    [self.leftButton setImage:nil forState:UIControlStateNormal];
    [self.leftButton addSubview:self.circleIcon];
    [self.circleIcon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.mas_equalTo(self.leftButton.mas_centerX);
        make.width.mas_equalTo(22.f);
        make.centerY.mas_equalTo(self.leftButton.mas_centerY);
        make.height.mas_equalTo(22.f);
    }];
    [self resetDevicesNum];
    [self.rightButton setImage:LOADIMAGE(@"scanRightAboutIcon", @"png") forState:UIControlStateNormal];
    [self.view setBackgroundColor:RGBCOLOR(237, 243, 250)];
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0,
                                                                  0,
                                                                  kScreenWidth - 2 * offset_X,
                                                                  searchButtonHeight + 2 * offset_X)];
    [headerView addSubview:self.searchButton];
    [self.searchButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(0);
        make.right.mas_equalTo(0);
        make.top.mas_equalTo(offset_X);
        make.height.mas_equalTo(searchButtonHeight);
    }];
    [self.view addSubview:headerView];
    [headerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(offset_X);
        make.right.mas_equalTo(-offset_X);
        make.top.mas_equalTo(0);
        make.height.mas_equalTo(searchButtonHeight + 2 * offset_X);
    }];
    [self.view addSubview:self.tableView];
    [self.tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(10.f);
        make.right.mas_equalTo(-10.f);
        make.top.mas_equalTo(headerView.mas_bottom).mas_offset(0);
        make.bottom.mas_equalTo(-5);
    }];
}

#pragma mark - setter & getter

- (HCKScanSearchButton *)searchButton{
    if (!_searchButton) {
        _searchButton = [[HCKScanSearchButton alloc] init];
        [_searchButton setBackgroundColor:COLOR_WHITE_MACROS];
        [_searchButton.layer setMasksToBounds:YES];
        [_searchButton.layer setCornerRadius:4.f];
        _searchButton.searchConditions = [@[] mutableCopy];
        WS(weakSelf);
        _searchButton.clearSearchConditionsBlock = ^{
            weakSelf.sortModel.isOpen = NO;
            weakSelf.sortModel.searchName = @"";
            weakSelf.sortModel.sortRssi = -127;
            weakSelf.leftButton.selected = NO;
            [weakSelf leftButtonMethod];
        };
        _searchButton.searchButtonPressedBlock = ^{
            [weakSelf serachButtonPressed];
        };
    }
    return _searchButton;
}

- (UIImageView *)circleIcon{
    if (!_circleIcon) {
        _circleIcon = [[UIImageView alloc] init];
        _circleIcon.image = LOADIMAGE(@"scanRefresh", @"png");
    }
    return _circleIcon;
}

- (HCKBaseTableView *)tableView{
    if (!_tableView) {
        _tableView = [[HCKBaseTableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        _tableView.delegate = self;
        _tableView.dataSource = self;
    }
    return _tableView;
}

- (NSMutableArray *)dataList{
    if (!_dataList) {
        _dataList = [NSMutableArray array];
    }
    return _dataList;
}

- (HCKSortModel *)sortModel{
    if (!_sortModel) {
        _sortModel = [[HCKSortModel alloc] init];
    }
    return _sortModel;
}

@end
