//
//  HCKEddStoneURLCell.m
//  HCKEddStone
//
//  Created by aa on 2017/11/29.
//  Copyright © 2017年 HCK. All rights reserved.
//

#import "HCKEddStoneURLCell.h"

static NSString *const HCKEddStoneURLCellIdenty = @"HCKEddStoneURLCellIdenty";

static CGFloat const msgLabelWidth = 60.f;
static CGFloat const offset_X = 10.f;
static CGFloat const offset_Y = 10.f;
static CGFloat const leftIconWidth = 13.f;
static CGFloat const leftIconHeight = 13.f;

#define msgFont HCKFont(12.f)

@interface HCKEddStoneURLCell()

/**
 小蓝点
 */
@property (nonatomic, strong)UIImageView *leftIcon;

/**
 类型,URL
 */
@property (nonatomic, strong)UILabel *typeLabel;

/**
 RSSI@0m
 */
@property (nonatomic, strong)UILabel *rssiLabel;

/**
 发射功率
 */
@property (nonatomic, strong)UILabel *txPowerLabel;

/**
 Link
 */
@property (nonatomic, strong)UILabel *linkLabel;

/**
 Link值
 */
@property (nonatomic, strong)UILabel *linkIDLabel;

@property (nonatomic, strong)UIView *linkLine;

@end

@implementation HCKEddStoneURLCell

+ (HCKEddStoneURLCell *)initCellWithTableView:(UITableView *)tableView{
    HCKEddStoneURLCell *cell = [tableView dequeueReusableCellWithIdentifier:HCKEddStoneURLCellIdenty];
    if (!cell) {
        cell = [[HCKEddStoneURLCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:HCKEddStoneURLCellIdenty];
    }
    return cell;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self.contentView addSubview:self.leftIcon];
        [self.contentView addSubview:self.typeLabel];
        [self.contentView addSubview:self.rssiLabel];
        [self.contentView addSubview:self.txPowerLabel];
        [self.contentView addSubview:self.linkLabel];
        [self.contentView addSubview:self.linkIDLabel];
    }
    return self;
}

#pragma mark - 父类方法
- (void)layoutSubviews{
    [super layoutSubviews];
    if (!self.beacon) {
        return;
    }
    [self.leftIcon mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(offset_X);
        make.width.mas_equalTo(leftIconWidth);
        make.top.mas_equalTo(offset_Y);
        make.height.mas_equalTo(leftIconHeight);
    }];
    [self.typeLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.leftIcon.mas_right).mas_offset(5.f);
        make.width.mas_equalTo(100.f);
        make.centerY.mas_equalTo(self.leftIcon.mas_centerY);
        make.height.mas_equalTo(HCKFont(15).lineHeight);
    }];
    [self.rssiLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.typeLabel.mas_right).mas_offset(10.f);
        make.width.mas_equalTo(msgLabelWidth);
        make.centerY.mas_equalTo(self.typeLabel.mas_centerY);
        make.height.mas_equalTo(msgFont.lineHeight);
    }];
    [self.txPowerLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.rssiLabel.mas_right).mas_offset(5.f);
        make.right.mas_equalTo(-offset_X);
        make.centerY.mas_equalTo(self.typeLabel.mas_centerY);
        make.height.mas_equalTo(msgFont.lineHeight);
    }];
    [self.linkLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.typeLabel.mas_left);
        make.width.mas_equalTo(self.typeLabel.mas_width);
        make.top.mas_equalTo(self.typeLabel.mas_bottom).mas_offset(5.f);
        make.height.mas_equalTo(msgFont.lineHeight);
    }];
    CGSize lineIDSize = [NSString sizeWithText:self.linkIDLabel.text
                                       andFont:self.linkIDLabel.font
                                    andMaxSize:CGSizeMake(MAXFLOAT, msgFont.lineHeight)];
    CGFloat lineIDWidth = lineIDSize.width;
    if (lineIDWidth > self.contentView.size.width - (offset_X + leftIconWidth + 100 + 5.f)) {
        lineIDWidth = self.contentView.size.width - (offset_X + leftIconWidth + 100 + 5.f);
    }
    [self.linkIDLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.rssiLabel.mas_left);
        make.width.mas_equalTo(lineIDWidth);
        make.top.mas_equalTo(self.linkLabel.mas_top);
        make.height.mas_equalTo(msgFont.lineHeight);
    }];
    [self.linkLine mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(0);
        make.right.mas_equalTo(0);
        make.bottom.mas_equalTo(0);
        make.height.mas_equalTo(CUTTING_LINE_HEIGHT);
    }];
}

#pragma mark - event method
- (void)linkUrlPressed{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:self.beacon.shortUrl]
                                       options:@{}
                             completionHandler:nil];
}

#pragma mark - Public method

- (void)setBeacon:(MKReceiveURLBeacon *)beacon{
    _beacon = nil;
    _beacon = beacon;
    if (!_beacon) {
        return;
    }
    if (ValidNum(_beacon.txPower)) {
        [self.txPowerLabel setText:[NSString stringWithFormat:@"%@dBm",stringFromInteger([_beacon.txPower integerValue])]];
    }
    if (ValidStr(_beacon.shortUrl)) {
        [self.linkIDLabel setText:_beacon.shortUrl];
    }
    [self setNeedsLayout];
}

#pragma mark - Private method
- (UILabel *)createLabelWithFont:(UIFont *)font{
    UILabel *label = [[UILabel alloc] init];
    label.textColor = DEFAULT_TEXT_COLOR;
    label.textAlignment = NSTextAlignmentLeft;
    label.font = font;
    return label;
}

#pragma mark - setter & getter
- (UIImageView *)leftIcon{
    if (!_leftIcon) {
        _leftIcon = [[UIImageView alloc] init];
        _leftIcon.image = LOADIMAGE(@"littleBluePoint", @"png");
    }
    return _leftIcon;
}

- (UILabel *)typeLabel{
    if (!_typeLabel) {
        _typeLabel = [self createLabelWithFont:HCKFont(15.f)];
        _typeLabel.text = @"URL";
    }
    return _typeLabel;
}

- (UILabel *)rssiLabel{
    if (!_rssiLabel) {
        _rssiLabel = [self createLabelWithFont:msgFont];
        _rssiLabel.text = @"RSSI@0m:";
    }
    return _rssiLabel;
}

- (UILabel *)txPowerLabel{
    if (!_txPowerLabel) {
        _txPowerLabel = [self createLabelWithFont:msgFont];
    }
    return _txPowerLabel;
}

- (UILabel *)linkLabel{
    if (!_linkLabel) {
        _linkLabel = [self createLabelWithFont:msgFont];
        _linkLabel.textColor = RGBCOLOR(184, 184, 184);
        _linkLabel.text = @"Link";
    }
    return _linkLabel;
}

- (UILabel *)linkIDLabel{
    if (!_linkIDLabel) {
        _linkIDLabel = [self createLabelWithFont:msgFont];
        _linkIDLabel.numberOfLines = 0;
        _linkIDLabel.textColor = [UIColor blueColor];
        [_linkIDLabel addSubview:self.linkLine];
        [_linkIDLabel addTapAction:self selector:@selector(linkUrlPressed)];
    }
    return _linkIDLabel;
}

- (UIView *)linkLine{
    if (!_linkLine) {
        _linkLine = [[UIView alloc] init];
        _linkLine.backgroundColor = [UIColor blueColor];
    }
    return _linkLine;
}

@end
