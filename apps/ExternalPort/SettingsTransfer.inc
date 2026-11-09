// Display preferences only; never import credentials, paths or a game-reading request.
static NSError *NSPConfigError(NSString *text) {
    return [NSError errorWithDomain:@"FanProMAX.Settings" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];
}
static NSData *NSPEncodeSettings(NSDictionary *settings,NSError **error) {
    NSMutableDictionary *values=[NSPNormalizedSettings(settings) mutableCopy];[values removeObjectForKey:@"sampling"];
    return [NSJSONSerialization dataWithJSONObject:@{@"format":@"fanpromax-display-settings",@"schema":@1,@"settings":values}
        options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:error];
}
static NSDictionary *NSPDecodeSettings(NSData *data,NSDictionary *current,NSError **error) {
    const auto fail=[&](NSString *message)->NSDictionary * {if(error)*error=NSPConfigError(message);return nil;};
    if(!data || data.length>65536)return fail(@"配置为空或超过 64 KB。");
    id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if(![root isKindOfClass:NSDictionary.class])return fail(@"文件不是有效的显示配置。");
    id schema=root[@"schema"];
    if(![root[@"format"] isEqual:@"fanpromax-display-settings"] || ![schema isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)schema)==CFBooleanGetTypeID() || [schema doubleValue]!=1)
        return fail(@"不是受支持的 FanProMAX iOS 显示配置。");
    NSDictionary *values=root[@"settings"];
    if(![values isKindOfClass:NSDictionary.class])return fail(@"配置中缺少显示参数。");
    NSMutableDictionary *merged=[NSPNormalizedSettings(current) mutableCopy];NSDictionary *defaults=NSPDefaults();
    NSSet *numeric=[NSSet setWithArray:@[@"label_scale",@"overlay_opacity",@"line_width",@"radar_range",@"radar_size",@"orientation",@"display_distance"]];
    for(id key in values) {
        if(![key isKindOfClass:NSString.class] || !defaults[key])return fail(@"配置含有不支持的参数。");
        if([key isEqual:@"sampling"])continue;
        id value=values[key];
        if(![value isKindOfClass:NSNumber.class] || !std::isfinite([value doubleValue]))return fail(@"显示参数类型不正确。");
        const bool boolean=CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID();
        if([numeric containsObject:key] ? boolean : ([value doubleValue]!=0 && [value doubleValue]!=1))
            return fail(@"显示参数类型不正确。");
        merged[key]=value;
    }
    // Keep current game-reading state; imported preferences cannot enable it.
    return NSPNormalizedSettings(merged);
}
