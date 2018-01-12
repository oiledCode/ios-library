/* Copyright 2017 Urban Airship and Contributors */

#import "UAJSONValueMatcher.h"
#import "NSJSONSerialization+UAAdditions.h"
#import "UAVersionMatcher+Internal.h"
#import "UAJSONPredicate.h"

@interface UAJSONValueMatcher ()
@property(nonatomic, strong) NSNumber *atLeast;
@property(nonatomic, strong) NSNumber *atMost;
@property(nonatomic, strong) NSNumber *equalsNumber;
@property(nonatomic, copy) NSString *equalsString;
@property(nonatomic, assign) NSNumber *isPresent;
@property(nonatomic, copy) NSString *versionConstraint;
@property(nonatomic, strong) UAVersionMatcher *versionMatcher;
@property(nonatomic, strong) UAJSONPredicate *arrayPredicate;
@property(nonatomic, strong) NSNumber *arrayIndex;
@end

NSString *const UAJSONValueMatcherAtMost = @"at_most";
NSString *const UAJSONValueMatcherAtLeast = @"at_least";
NSString *const UAJSONValueMatcherEquals = @"equals";
NSString *const UAJSONValueMatcherIsPresent = @"is_present";
NSString *const UAJSONValueMatcherVersionConstraint = @"version";
NSString *const UAJSONValueMatcherArrayContains = @"array_contains";
NSString *const UAJSONValueMatcherArrayIndex = @"index";

NSString * const UAJSONValueMatcherErrorDomain = @"com.urbanairship.json_value_matcher";


@implementation UAJSONValueMatcher

- (NSDictionary *)payload {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];

    [payload setValue:self.equalsNumber ?: self.equalsString forKey:UAJSONValueMatcherEquals];
    [payload setValue:self.atLeast forKey:UAJSONValueMatcherAtLeast];
    [payload setValue:self.atMost forKey:UAJSONValueMatcherAtMost];
    [payload setValue:self.isPresent forKey:UAJSONValueMatcherIsPresent];
    [payload setValue:self.versionConstraint forKey:UAJSONValueMatcherVersionConstraint];
    [payload setValue:self.arrayIndex forKey:UAJSONValueMatcherArrayIndex];
    [payload setValue:self.arrayPredicate forKey:UAJSONValueMatcherArrayContains];

    return payload;
}

- (BOOL)evaluateObject:(id)value {
    if (self.isPresent != nil) {
        return [self.isPresent boolValue] == (value != nil);
    }

    if (self.equalsString && ![self.equalsString isEqual:value]) {
        return NO;
    }

    NSNumber *numberValue = [value isKindOfClass:[NSNumber class]] ? value : nil;
    NSString *stringValue = [value isKindOfClass:[NSString class]] ? value : nil;

    if (self.equalsNumber && !(numberValue && [self.equalsNumber isEqualToNumber:numberValue])) {
        return NO;
    }

    if (self.atLeast && !(numberValue && [self.atLeast compare:numberValue] != NSOrderedDescending)) {
        return NO;
    }

    if (self.atMost && !(numberValue && [self.atMost compare:numberValue] != NSOrderedAscending)) {
        return NO;
    }
    
    if (self.versionMatcher && !(stringValue && [self.versionMatcher evaluateObject:value])) {
        return NO;
    }

    if (self.arrayPredicate) {
        if (![value isKindOfClass:[NSArray class]]) {
            return NO;
        }

        NSArray *array = value;

        if (self.arrayIndex) {
            NSInteger index = [self.arrayIndex integerValue];
            if (index < 0 || index >= array.count) {
                return NO;
            }
            return [self.arrayPredicate evaluateObject:array[index]];
        } else {
            for (id value in array) {
                if ([self.arrayPredicate evaluateObject:value]) {
                    return YES;
                }
            }
            return NO;
        }
    }
    
    return YES;
}

+ (instancetype)matcherWhereNumberAtLeast:(NSNumber *)number {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.atLeast = number;
    return matcher;
}

+ (instancetype)matcherWhereNumberAtLeast:(NSNumber *)lowerNumber atMost:(NSNumber *)higherNumber {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.atLeast = lowerNumber;
    matcher.atMost = higherNumber;
    return matcher;
}

+ (instancetype)matcherWhereNumberAtMost:(NSNumber *)number {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.atMost = number;
    return matcher;
}

+ (instancetype)matcherWhereNumberEquals:(NSNumber *)number {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.equalsNumber = number;
    return matcher;
}

+ (instancetype)matcherWhereStringEquals:(NSString *)string {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.equalsString = string;
    return matcher;
}

+ (instancetype)matcherWhereValueIsPresent:(BOOL)present {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.isPresent = @(present);
    return matcher;
}

+ (nullable instancetype)matcherWithVersionConstraint:(NSString *)versionConstraint {
    UAVersionMatcher *versionMatcher = [UAVersionMatcher matcherWithVersionConstraint:versionConstraint];
    
    if (!versionMatcher) {
        return nil;
    }
    
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.versionConstraint = versionConstraint;
    matcher.versionMatcher = versionMatcher;
    return matcher;
}

+ (nullable instancetype)matcherWithArrayContainsPredicate:(UAJSONPredicate *)predicate {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.arrayPredicate = predicate;
    return matcher;
}

+ (nullable instancetype)matcherWithArrayContainsPredicate:(UAJSONPredicate *)predicate atIndex:(NSUInteger)index {
    UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
    matcher.arrayPredicate = predicate;
    matcher.arrayIndex = @(index);
    return matcher;
}

+ (instancetype)matcherWithJSON:(id)json error:(NSError **)error {
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            NSString *msg = [NSString stringWithFormat:@"Attempted to deserialize invalid object: %@", json];
            *error =  [NSError errorWithDomain:UAJSONValueMatcherErrorDomain
                                          code:UAJSONValueMatcherErrorCodeInvalidJSON
                                      userInfo:@{NSLocalizedDescriptionKey:msg}];
        }

        return nil;
    }

    if ([self isNumericMatcherExpression:json]) {
        UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
        matcher.atMost = json[UAJSONValueMatcherAtMost];
        matcher.atLeast = json[UAJSONValueMatcherAtLeast];
        matcher.equalsNumber = json[UAJSONValueMatcherEquals];
        return matcher;
    }

    if ([self isStringMatcherExpression:json]) {
        return [self matcherWhereStringEquals:json[UAJSONValueMatcherEquals]];
    }

    if ([self isPresentMatcherExpression:json]) {
        return [self matcherWhereValueIsPresent:[json[UAJSONValueMatcherIsPresent] boolValue]];
    }

    if ([self isArrayMatcherExpression:json]) {
        UAJSONValueMatcher *matcher = [[UAJSONValueMatcher alloc] init];
        matcher.arrayPredicate = [UAJSONPredicate predicateWithJSON:json[UAJSONValueMatcherArrayContains] error:error];
        matcher.arrayIndex = json[UAJSONValueMatcherArrayIndex];

        if (!matcher.arrayPredicate) {
            return nil;
        }

        return matcher;
    }

    UAJSONValueMatcher *matcher = [self matcherWithVersionConstraint:json[UAJSONValueMatcherVersionConstraint]];
    if (matcher) {
        return matcher;
    }
    
    if (error) {
        NSString *msg = [NSString stringWithFormat:@"Invalid value matcher: %@", json];
        *error =  [NSError errorWithDomain:UAJSONValueMatcherErrorDomain
                                      code:UAJSONValueMatcherErrorCodeInvalidJSON
                                  userInfo:@{NSLocalizedDescriptionKey:msg}];
    }


    // Invalid
    return nil;
}


+ (BOOL)isNumericMatcherExpression:(NSDictionary *)expression {
    // "equals": number | "at_least": number | "at_most": number | "at_least": number, "at_most": number
    if ([expression count] == 0 || [expression count] > 2) {
        return NO;
    }

    if ([expression count] == 1) {
        return [expression[UAJSONValueMatcherEquals] isKindOfClass:[NSNumber class]] ||
        [expression[UAJSONValueMatcherAtLeast] isKindOfClass:[NSNumber class]] ||
        [expression[UAJSONValueMatcherAtMost] isKindOfClass:[NSNumber class]];
    }

    if ([expression count] == 2) {
        return [expression[UAJSONValueMatcherAtLeast] isKindOfClass:[NSNumber class]] &&
        [expression[UAJSONValueMatcherAtMost] isKindOfClass:[NSNumber class]];
    }

    return [expression[UAJSONValueMatcherEquals] isKindOfClass:[NSNumber class]];
}

+ (BOOL)isStringMatcherExpression:(NSDictionary *)expression {
    if ([expression count] != 1) {
        return NO;
    }

    id subexp = expression[UAJSONValueMatcherEquals];
    return [subexp isKindOfClass:[NSString class]];
}

+ (BOOL)isPresentMatcherExpression:(NSDictionary *)expression {
    if ([expression count] != 1) {
        return NO;
    }

    id subexp = expression[UAJSONValueMatcherIsPresent];

    // Note: it's not possible to reflect a pure boolean value here so this will accept non-binary numbers as well
    return [subexp isKindOfClass:[NSNumber class]];
}

+ (BOOL)isArrayMatcherExpression:(NSDictionary *)expression {
    if ([expression count] == 0 || [expression count] > 2) {
        return NO;
    }

    if ([expression count] == 1) {
        return [expression[UAJSONValueMatcherArrayContains] isKindOfClass:[NSDictionary class]];
    }

    return [expression[UAJSONValueMatcherArrayContains] isKindOfClass:[NSDictionary class]] &&
    [expression[UAJSONValueMatcherArrayIndex] isKindOfClass:[NSNumber class]];
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    
    if (![other isKindOfClass:[self class]]) {
        return NO;
    }
    
    return [self isEqualToJSONValueMatcher:(UAJSONValueMatcher *)other];
}

- (BOOL)isEqualToJSONValueMatcher:(nullable UAJSONValueMatcher *)matcher {
    if (self.equalsNumber && (!matcher.equalsNumber || ![self.equalsNumber isEqualToNumber:matcher.equalsNumber])) {
        return NO;
    }
    if (self.equalsString && (!matcher.equalsString || ![self.equalsString isEqualToString:matcher.equalsString])) {
        return NO;
    }
    if (self.atLeast && (!matcher.atLeast || ![self.atLeast isEqualToNumber:matcher.atLeast])) {
        return NO;
    }
    if (self.atMost && (!matcher.atMost || ![self.atMost isEqualToNumber:matcher.atMost])) {
        return NO;
    }
    if (self.isPresent && (!matcher.isPresent || ![self.isPresent isEqualToNumber:matcher.isPresent])) {
        return NO;
    }
    if (self.versionConstraint && (!matcher.versionConstraint || ![self.versionConstraint isEqualToString:matcher.versionConstraint])) {
        return NO;
    }
    if (self.arrayPredicate != matcher.arrayPredicate && ![self.arrayPredicate isEqual:matcher.arrayPredicate]) {
        return NO;
    }
    if (self.arrayIndex != matcher.arrayIndex && ![self.arrayIndex isEqual:matcher.arrayIndex]) {
        return NO;
    }
    return YES;
}

- (NSUInteger)hash {
    NSUInteger result = 1;
    result = 31 * result + [self.equalsNumber hash];
    result = 31 * result + [self.atLeast hash];
    result = 31 * result + [self.atMost hash];
    result = 31 * result + [self.isPresent hash];
    result = 31 * result + [self.versionConstraint hash];
    result = 31 * result + [self.arrayPredicate hash];
    result = 31 * result + [self.arrayIndex hash];
    return result;
}

@end
