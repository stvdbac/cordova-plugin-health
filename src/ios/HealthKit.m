#import "HealthKit.h"
#import "HKHealthStore+AAPLExtensions.h"
#import "WorkoutActivityConversion.h"
#import <Cordova/CDV.h>

static NSString *const HKSampleKeyStartDate = @"startDate";
static NSString *const HKSampleKeyEndDate = @"endDate";
static NSString *const HKSampleKeySampleType = @"sampleType";
static NSString *const HKSampleKeyUnit = @"unit";
static NSString *const HKSampleKeyValue = @"value";
static NSString *const HKSampleKeyCorrelationType = @"correlationType";
static NSString *const HKSampleKeyObjects = @"samples";
static NSString *const HKSampleKeyMetadata = @"metadata";
static NSString *const HKSampleKeyUUID = @"UUID";


@implementation HealthKit

- (CDVPlugin*) initWithWebView:(UIWebView*)theWebView {
  self = (HealthKit*)[super initWithWebView:theWebView];
  if (self) {
    _healthStore = [HKHealthStore new];
  }
  return self;
}

- (void) available:(CDVInvokedUrlCommand*)command {
  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:[HKHealthStore isHealthDataAvailable]];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void) requestAuthorization:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  
  // read types
  NSArray *readTypes = [args objectForKey:@"readTypes"];
  NSSet *readDataTypes = [[NSSet alloc] init];
  for (int i=0; i<[readTypes count]; i++) {
    NSString *elem = [readTypes objectAtIndex:i];
    HKObjectType *type = [self getHKObjectType:elem];
    if (type == nil) {
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"readTypes contains an invalid value"];
      [result setKeepCallbackAsBool:YES];
      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      // not returning deliberately to be future proof; other permissions are still asked
    } else {
      readDataTypes = [readDataTypes setByAddingObject:type];
    }
  }
  
  // write types
  NSArray *writeTypes = [args objectForKey:@"writeTypes"];
  NSSet *writeDataTypes = [[NSSet alloc] init];
  for (int i=0; i<[writeTypes count]; i++) {
    NSString *elem = [writeTypes objectAtIndex:i];
    HKObjectType *type = [self getHKObjectType:elem];
    if (type == nil) {
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"writeTypes contains an invalid value"];
      [result setKeepCallbackAsBool:YES];
      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      // not returning deliberately to be future proof; other permissions are still asked
    } else {
      writeDataTypes = [writeDataTypes setByAddingObject:type];
    }
  }
  
  [self.healthStore requestAuthorizationToShareTypes:writeDataTypes readTypes:readDataTypes completion:^(BOOL success, NSError *error) {
    if (success) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    }
  }];
}

- (void) checkAuthStatus:(CDVInvokedUrlCommand*)command {
  // Note for doc, if status = denied, prompt user to go to settings or the Health app
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  NSString *checkType = [args objectForKey:@"type"];

  HKObjectType *type = [self getHKObjectType:checkType];
  if (type == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"type is an invalid value"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  } else {
    HKAuthorizationStatus status = [self.healthStore authorizationStatusForType:type];
    NSString *result;
    if (status == HKAuthorizationStatusNotDetermined) {
      result = @"undetermined";
    } else if (status == HKAuthorizationStatusSharingDenied) {
      result = @"denied";
    } else if (status == HKAuthorizationStatusSharingAuthorized) {
      result = @"authorized";
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }
}

// TODO make this a more generic function which can save anything
/*
- (void) saveNutrition:(CDVInvokedUrlCommand*)command {
  HKQuantityType *quantityType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierDietaryEnergyConsumed];
  HKQuantity *quantity = [HKQuantity quantityWithUnit:@"joules" doubleValue:300];
  NSDate *now = [NSDate init];
  NSDictionary *metaData = ["HKMetadataKeyFoodType":"Ham Sandwich"];
  HKQuantitySample *calorieSample = HKQuantitySample(type: quantityType, quantity:quantity, startDate:now, endDate:now, metadata:metadata);
  save sample (see workout)
  .. etc
}
 */

- (void) saveWorkout:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  
  NSString *activityType = [args objectForKey:@"activityType"];
  NSString *quantityType = [args objectForKey:@"quantityType"]; // TODO verify this value
  
  HKWorkoutActivityType activityTypeEnum = [WorkoutActivityConversion convertStringToHKWorkoutActivityType:activityType];
  
  BOOL requestReadPermission = [args objectForKey:@"requestReadPermission"] == nil ? YES : [[args objectForKey:@"requestReadPermission"] boolValue];
  
  // optional energy
  NSNumber *energy = [args objectForKey:@"energy"];
  NSString *energyUnit = [args objectForKey:@"energyUnit"];
  HKQuantity *nrOfEnergyUnits = nil;
  if (energy != nil) {
    HKUnit *preferredEnergyUnit = [self getUnit:energyUnit:@"HKEnergyUnit"];
    if (preferredEnergyUnit == nil) {
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"invalid energyUnit was passed"];
      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      return;
    }
    nrOfEnergyUnits = [HKQuantity quantityWithUnit:preferredEnergyUnit doubleValue:energy.doubleValue];
  }
  
  // optional distance
  NSNumber *distance = [args objectForKey:@"distance"];
  NSString *distanceUnit = [args objectForKey:@"distanceUnit"];
  HKQuantity *nrOfDistanceUnits = nil;
  if (distance != (id)[NSNull null]) {
    HKUnit *preferredDistanceUnit = [self getUnit:distanceUnit:@"HKLengthUnit"];
    if (preferredDistanceUnit == nil) {
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"invalid distanceUnit was passed"];
      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      return;
    }
    nrOfDistanceUnits = [HKQuantity quantityWithUnit:preferredDistanceUnit doubleValue:distance.doubleValue];
  }
  
  int duration = 0;
  NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"startDate"] doubleValue]];
  
  
  NSDate *endDate;
  if ([args objectForKey:@"duration"]) {
    duration = [[args objectForKey:@"duration"] intValue];
    endDate = [NSDate dateWithTimeIntervalSince1970:startDate.timeIntervalSince1970 + duration];
  } else if ([args objectForKey:@"endDate"]) {
    endDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"endDate"] doubleValue]];
  } else {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"no duration or endDate was set"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  NSSet *types = [NSSet setWithObjects:[HKWorkoutType workoutType], [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierActiveEnergyBurned], [HKQuantityType quantityTypeForIdentifier:quantityType], nil];
  [self.healthStore requestAuthorizationToShareTypes:types readTypes:requestReadPermission ? types : nil completion:^(BOOL success, NSError *error) {
    if (!success) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    } else {
      HKWorkout *workout = [HKWorkout workoutWithActivityType:activityTypeEnum
                                                    startDate:startDate
                                                      endDate:endDate
                                                     duration:0 // the diff between start and end is used
                                            totalEnergyBurned:nrOfEnergyUnits
                                                totalDistance:nrOfDistanceUnits
                                                     metadata:nil]; // TODO find out if needed
      [self.healthStore saveObject:workout withCompletion:^(BOOL success, NSError *innerError) {
        if (success) {
          // now store the samples, so it shows up in the health app as well (pass this in as an option?)
          if (energy != nil) {
            HKQuantitySample *sampleActivity = [HKQuantitySample quantitySampleWithType:[HKQuantityType quantityTypeForIdentifier:
                                                                                         quantityType]
                                                                               quantity:nrOfDistanceUnits
                                                                              startDate:startDate
                                                                                endDate:endDate];
            HKQuantitySample *sampleCalories = [HKQuantitySample quantitySampleWithType:[HKQuantityType quantityTypeForIdentifier:
                                                                                         HKQuantityTypeIdentifierActiveEnergyBurned]
                                                                               quantity:nrOfEnergyUnits
                                                                              startDate:startDate
                                                                                endDate:endDate];
            NSArray *samples = [NSArray arrayWithObjects:sampleActivity, sampleCalories, nil];
            
            [self.healthStore addSamples:samples toWorkout:workout completion:^(BOOL success, NSError *mostInnerError) {
              if (success) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                });
              } else {
                dispatch_sync(dispatch_get_main_queue(), ^{
                  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR  messageAsString:mostInnerError.localizedDescription];
                  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                });
              }
            }];
          }
        } else {
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:innerError.localizedDescription];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        }
      }];
    }
  }];
}

- (void) findWorkouts:(CDVInvokedUrlCommand*)command {
  NSPredicate *workoutPredicate = nil;
  // TODO if a specific workouttype was passed, use that
  if (false) {
    workoutPredicate = [HKQuery predicateForWorkoutsWithWorkoutActivityType:HKWorkoutActivityTypeCycling];
  }
  
  NSSet *types = [NSSet setWithObjects:[HKWorkoutType workoutType], nil];
  [self.healthStore requestAuthorizationToShareTypes:nil readTypes:types completion:^(BOOL success, NSError *error) {
    if (!success) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    } else {
      
      
      HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:[HKWorkoutType workoutType] predicate:workoutPredicate limit:HKObjectQueryNoLimit sortDescriptors:nil resultsHandler:^(HKSampleQuery *query, NSArray *results, NSError *error) {
        if (error) {
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        } else {
          NSDateFormatter *df = [[NSDateFormatter alloc] init];
          [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
          
          NSMutableArray *finalResults = [[NSMutableArray alloc] initWithCapacity:results.count];
          
          for (HKWorkout *workout in results) {
            NSString *workoutActivity = [WorkoutActivityConversion convertHKWorkoutActivityTypeToString:workout.workoutActivityType];
//            HKQuantity *teb = workout.totalEnergyBurned.description;
//            HKQuantity *td = [workout.totalDistance.description;
            NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                            [NSNumber numberWithDouble:workout.duration], @"duration",
                                            [df stringFromDate:workout.startDate], @"startDate",
                                            [df stringFromDate:workout.endDate], @"endDate",
                                            workout.source.bundleIdentifier, @"sourceBundleId",
                                            workoutActivity, @"activityType",
                                            nil
                                          ];
            
            [finalResults addObject:entry];
          }
          
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:finalResults];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        }
      }];
      [self.healthStore executeQuery:query];
    }
  }];
}




/*
- (void) addSamplesToWorkout:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];

  NSDate *start = [NSDate date]; // TODO pass in
  NSDate *end = [NSDate date]; // TODO pass in

  // TODO pass in workoutactivity
  HKWorkout *workout = [HKWorkout workoutWithActivityType:HKWorkoutActivityTypeRunning
                                                startDate:start
                                                  endDate:end];
  NSArray *samples = [NSArray init];

  [self.healthStore addSamples:samples toWorkout:workout completion:^(BOOL success, NSError *error) {
    if (success) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    }
  }];
}
 */

- (void) saveWeight:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  NSString *unit = [args objectForKey:@"unit"];
  NSNumber *amount = [args objectForKey:@"amount"];
  NSDate *date = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"date"] doubleValue]];
  BOOL requestReadPermission = [args objectForKey:@"requestReadPermission"] == nil ? YES : [[args objectForKey:@"requestReadPermission"] boolValue];
  
  if (amount == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"no amount was set"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  HKUnit *preferredUnit = [self getUnit:unit:@"HKMassUnit"];
  if (preferredUnit == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"invalid unit was passed"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  HKQuantityType *weightType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBodyMass];
  NSSet *requestTypes = [NSSet setWithObjects: weightType, nil];
  [self.healthStore requestAuthorizationToShareTypes:requestTypes readTypes:requestReadPermission ? requestTypes : nil completion:^(BOOL success, NSError *error) {
    if (success) {
      HKQuantity *weightQuantity = [HKQuantity quantityWithUnit:preferredUnit doubleValue:[amount doubleValue]];
      HKQuantitySample *weightSample = [HKQuantitySample quantitySampleWithType:weightType quantity:weightQuantity startDate:date endDate:date];
      [self.healthStore saveObject:weightSample withCompletion:^(BOOL success, NSError* errorInner) {
        if (success) {
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        } else {
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorInner.localizedDescription];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        }
      }];
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    }
  }];
}

// TODO do we get back a date? Yes, see aapl_mostRecentQuantitySampleOfType
- (void) readWeight:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  NSString *unit = [args objectForKey:@"unit"];
  BOOL requestWritePermission = [args objectForKey:@"requestWritePermission"] == nil ? YES : [[args objectForKey:@"requestWritePermission"] boolValue];
  
  HKUnit *preferredUnit = [self getUnit:unit:@"HKMassUnit"];
  if (preferredUnit == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"invalid unit was passed"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  // Query to get the user's latest weight, if it exists.
  HKQuantityType *weightType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBodyMass];
  NSSet *requestTypes = [NSSet setWithObjects: weightType, nil];
  // always ask for read and write permission if the app uses both, because granting read will remove write for the same type :(
  [self.healthStore requestAuthorizationToShareTypes:requestWritePermission ? requestTypes : nil readTypes:requestTypes completion:^(BOOL success, NSError *error) {
    if (success) {
      [self.healthStore aapl_mostRecentQuantitySampleOfType:weightType predicate:nil completion:^(HKQuantity *mostRecentQuantity, NSDate *mostRecentDate, NSError *errorInner) {
        if (mostRecentQuantity) {
          double usersWeight = [mostRecentQuantity doubleValueForUnit:preferredUnit];
          NSDateFormatter *df = [[NSDateFormatter alloc] init];
          [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
          NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                        [NSNumber numberWithDouble:usersWeight], @"value",
                                        unit, @"unit",
                                        [df stringFromDate:mostRecentDate], @"date",
                                        nil];
          dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:entry];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        } else {
          dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorInner.localizedDescription];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        }
      }];
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    }
  }];
}


- (void) saveHeight:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  NSString *unit = [args objectForKey:@"unit"];
  NSNumber *amount = [args objectForKey:@"amount"];
  NSDate *date = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"date"] doubleValue]];
  BOOL requestReadPermission = [args objectForKey:@"requestReadPermission"] == nil ? YES : [[args objectForKey:@"requestReadPermission"] boolValue];
  
  if (amount == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"no amount was set"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  HKUnit *preferredUnit = [self getUnit:unit:@"HKLengthUnit"];
  if (preferredUnit == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"invalid unit was passed"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  HKQuantityType *heightType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeight];
  NSSet *requestTypes = [NSSet setWithObjects: heightType, nil];
  [self.healthStore requestAuthorizationToShareTypes:requestTypes readTypes:requestReadPermission ? requestTypes : nil completion:^(BOOL success, NSError *error) {
    if (success) {
      HKQuantity *heightQuantity = [HKQuantity quantityWithUnit:preferredUnit doubleValue:[amount doubleValue]];
      HKQuantitySample *heightSample = [HKQuantitySample quantitySampleWithType:heightType quantity:heightQuantity startDate:date endDate:date];
      [self.healthStore saveObject:heightSample withCompletion:^(BOOL success, NSError* errorInner) {
        if (success) {
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        } else {
          dispatch_sync(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorInner.localizedDescription];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        }
      }];
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    }
  }];
}


- (void) readHeight:(CDVInvokedUrlCommand*)command {
  NSMutableDictionary *args = [command.arguments objectAtIndex:0];
  NSString *unit = [args objectForKey:@"unit"];
  BOOL requestWritePermission = [args objectForKey:@"requestWritePermission"] == nil ? YES : [[args objectForKey:@"requestWritePermission"] boolValue];
  
  HKUnit *preferredUnit = [self getUnit:unit:@"HKLengthUnit"];
  if (preferredUnit == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"invalid unit was passed"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  // Query to get the user's latest height, if it exists.
  HKQuantityType *heightType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeight];
  NSSet *requestTypes = [NSSet setWithObjects: heightType, nil];
  // always ask for read and write permission if the app uses both, because granting read will remove write for the same type :(
  [self.healthStore requestAuthorizationToShareTypes:requestWritePermission ? requestTypes : nil readTypes:requestTypes completion:^(BOOL success, NSError *error) {
    if (success) {
      [self.healthStore aapl_mostRecentQuantitySampleOfType:heightType predicate:nil completion:^(HKQuantity *mostRecentQuantity, NSDate *mostRecentDate, NSError *errorInner) { // TODO use
        if (mostRecentQuantity) {
          double usersHeight = [mostRecentQuantity doubleValueForUnit:preferredUnit];
          NSDateFormatter *df = [[NSDateFormatter alloc] init];
          [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
          NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                        [NSNumber numberWithDouble:usersHeight], @"value",
                                        unit, @"unit",
                                        [df stringFromDate:mostRecentDate], @"date",
                                        nil];
          dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:entry];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        } else {
          dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorInner.localizedDescription];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
          });
        }
      }];
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      });
    }
  }];
}

- (void) readGender:(CDVInvokedUrlCommand*)command {
  HKCharacteristicType *genderType = [HKObjectType characteristicTypeForIdentifier:HKCharacteristicTypeIdentifierBiologicalSex];
  [self.healthStore requestAuthorizationToShareTypes:nil readTypes:[NSSet setWithObjects: genderType, nil] completion:^(BOOL success, NSError *error) {
    if (success) {
      HKBiologicalSexObject *sex = [self.healthStore biologicalSexWithError:&error];
      if (sex) {
        NSString* gender = @"unknown";
        if (sex.biologicalSex == HKBiologicalSexMale) {
          gender = @"male";
        } else if (sex.biologicalSex == HKBiologicalSexFemale) {
          gender = @"female";
        }
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:gender];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      } else {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      }
    }
  }];
}

- (void) readDateOfBirth:(CDVInvokedUrlCommand*)command {
  // TODO pass in dateformat?
  NSDateFormatter *df = [[NSDateFormatter alloc] init];
  [df setDateFormat:@"yyyy-MM-dd"];
  HKCharacteristicType *birthdayType = [HKObjectType characteristicTypeForIdentifier:HKCharacteristicTypeIdentifierDateOfBirth];
  [self.healthStore requestAuthorizationToShareTypes:nil readTypes:[NSSet setWithObjects: birthdayType, nil] completion:^(BOOL success, NSError *error) {
    if (success) {
      NSDate *dateOfBirth = [self.healthStore dateOfBirthWithError:&error];
      if (dateOfBirth) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[df stringFromDate:dateOfBirth]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      } else {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      }
    }
  }];
}


- (void) monitorSampleType:(CDVInvokedUrlCommand*)command {

    NSMutableDictionary *args = [command.arguments objectAtIndex:0];
    NSString *sampleTypeString = [args objectForKey:@"sampleType"];
    HKSampleType *type = [self getHKSampleType:sampleTypeString];

    HKUpdateFrequency updateFrequency = HKUpdateFrequencyImmediate;

    if (type==nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"sampleType was invalid"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }

    // TODO use this an an anchor for an achored query
    //__block int *anchor = 0;

    NSLog(@"Setting up ObserverQuery");

    HKObserverQuery *query;
    query = [[HKObserverQuery alloc] initWithSampleType:type
                                              predicate:nil
                                          updateHandler:^(HKObserverQuery *query,
                                                          HKObserverQueryCompletionHandler handler,
                                                          NSError *error)
     {
         if (error) {

             handler();

             dispatch_sync(dispatch_get_main_queue(), ^{
                 CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                 [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
             });


         } else {

             handler();

             // TODO using a anchored query to return the new and updated values.
             // Until then use querySampleType({limit=1, ascending="T", endDate=new Date()}) to return the
             // last result


             dispatch_sync(dispatch_get_main_queue(), ^{
                 CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:sampleTypeString];
                 [result setKeepCallbackAsBool:YES];
                 [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
             });
         }
     }];



    // Make sure we get the updated immediately
    [self.healthStore enableBackgroundDeliveryForType:type frequency:updateFrequency withCompletion:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"Background devliery enabled %@", sampleTypeString);
        }
        else {
            NSLog(@"Background delivery not enabled for %@ because of %@", sampleTypeString, error);
        }

        NSLog(@"Executing ObserverQuery");
        [self.healthStore executeQuery:query];
        // TODO provide some kind of callback to stop monitoring this value, store the query in some kind
        // of WeakHashSet equilavent?

    }];
};



- (void) sumQuantityType:(CDVInvokedUrlCommand*)command {


    NSMutableDictionary *args = [command.arguments objectAtIndex:0];


    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"startDate"] longValue]];
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"endDate"] longValue]];
    NSString *sampleTypeString = [args objectForKey:@"sampleType"];
    NSString *unitString = [args objectForKey:@"unit"];
    HKQuantityType *type = [HKObjectType quantityTypeForIdentifier:sampleTypeString];


    if (type==nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"sampleType was invalid"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }



    NSPredicate *predicate = [HKQuery predicateForSamplesWithStartDate:startDate endDate:endDate options:HKQueryOptionStrictStartDate];
    HKStatisticsOptions sumOptions = HKStatisticsOptionCumulativeSum;
    HKStatisticsQuery *query;
    HKUnit *unit = unitString!=nil ? [HKUnit unitFromString:unitString] : [HKUnit countUnit];
    query = [[HKStatisticsQuery alloc] initWithQuantityType:type
                                    quantitySamplePredicate:predicate
                                                    options:sumOptions
                                          completionHandler:^(HKStatisticsQuery *query,
                                                              HKStatistics *result,
                                                              NSError *error)
             {
                 HKQuantity *sum = [result sumQuantity];
                 CDVPluginResult* response = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[sum doubleValueForUnit:unit]];
                 [self.commandDelegate sendPluginResult:response callbackId:command.callbackId];
             }];

    [self.healthStore executeQuery:query];
}

- (void) querySampleType:(CDVInvokedUrlCommand*)command {
    NSMutableDictionary *args = [command.arguments objectAtIndex:0];
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"startDate"] longValue]];
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:@"endDate"] longValue]];
    NSString *sampleTypeString = [args objectForKey:@"sampleType"];
    NSString *unitString = [args objectForKey:@"unit"];
    int limit = [args objectForKey:@"limit"] != nil ? [[args objectForKey:@"limit"] intValue] : 100;
    BOOL ascending = [args objectForKey:@"ascending"] != nil ? [[args objectForKey:@"ascending"] boolValue] : NO;

    HKSampleType *type = [self getHKSampleType:sampleTypeString];
    if (type==nil) {
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"sampleType was invalid"];
      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      return;
    }
    HKUnit *unit = unitString!=nil ? [HKUnit unitFromString:unitString] : nil;
    // TODO check that unit is compatible with sampleType if sample type of HKQuantityType
    NSPredicate *predicate = [HKQuery predicateForSamplesWithStartDate:startDate endDate:endDate options:HKQueryOptionStrictStartDate];

    NSSet *requestTypes = [NSSet setWithObjects: type, nil];
    [self.healthStore requestAuthorizationToShareTypes:nil readTypes:requestTypes completion:^(BOOL success, NSError *error) {
      if (success) {

        NSString *endKey = HKSampleSortIdentifierEndDate;
        NSSortDescriptor *endDateSort = [NSSortDescriptor sortDescriptorWithKey:endKey ascending:ascending];
        HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:type
                                                               predicate:predicate
                                                                   limit:limit
                                                         sortDescriptors:@[endDateSort]
                                                          resultsHandler:^(HKSampleQuery *query,
                                                                           NSArray *results,
                                                                           NSError *error)
                                {
                                  if (error) {
                                    dispatch_sync(dispatch_get_main_queue(), ^{
                                      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                                      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                                    });
                                  } else {

                                    NSDateFormatter *df = [[NSDateFormatter alloc] init];
                                    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];


                                    NSMutableArray *finalResults = [[NSMutableArray alloc] initWithCapacity:results.count];

                                    for (HKSample *sample in results) {

                                      NSDate *startSample = sample.startDate;
                                      NSDate *endSample = sample.endDate;

                                      NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                                    [df stringFromDate:startSample], @"startDate",
                                                                    [df stringFromDate:endSample], @"endDate",
                                                                    nil];

                                      if ([sample isKindOfClass:[HKCategorySample class]]) {
                                        HKCategorySample *csample = (HKCategorySample *)sample;
                                        [entry setValue:[NSNumber numberWithLong:csample.value] forKey:@"value"];
                                        [entry setValue:csample.categoryType.identifier forKey:@"catagoryType.identifier"];
                                        [entry setValue:csample.categoryType.description forKey:@"catagoryType.description"];
                                      } else if ([sample isKindOfClass:[HKCorrelationType class]]) {
                                        // TODO
                                      } else if ([sample isKindOfClass:[HKQuantitySample class]]) {
                                        HKQuantitySample *qsample = (HKQuantitySample *)sample;
                                        // TODO compare with unit
                                        [entry setValue:[NSNumber numberWithDouble:[qsample.quantity doubleValueForUnit:unit]] forKey:@"quantity"];

                                      } else if ([sample isKindOfClass:[HKCorrelationType class]]) {
                                        // TODO
                                      } else if ([sample isKindOfClass:[HKWorkout class]]) {
                                        HKWorkout *wsample = (HKWorkout*)sample;
                                        [entry setValue:[NSNumber numberWithDouble:wsample.duration] forKey:@"duration"];
                                      }

                                      [finalResults addObject:entry];
                                    }

                                    dispatch_sync(dispatch_get_main_queue(), ^{
                                      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:finalResults];
                                      [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                                    });
                                  }
                                }];

        [self.healthStore executeQuery:query];
      } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
          CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
          [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        });
      }
    }];
}
//New functions
- (void) queryCorrelationType:(CDVInvokedUrlCommand*)command {
    NSMutableDictionary *args = [command.arguments objectAtIndex:0];
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:HKSampleKeyStartDate] longValue]];
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:[[args objectForKey:HKSampleKeyEndDate] longValue]];
    NSString *correlationTypeString = [args objectForKey:HKSampleKeyCorrelationType];
    NSString *unitString = [args objectForKey:HKSampleKeyUnit];
    
    HKCorrelationType *type = (HKCorrelationType*)[self getHKSampleType:correlationTypeString];
    if (type==nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"sampleType was invalid"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
    HKUnit *unit = unitString!=nil ? [HKUnit unitFromString:unitString] : nil;
    // TODO check that unit is compatible with sampleType if sample type of HKQuantityType
    NSPredicate *predicate = [HKQuery predicateForSamplesWithStartDate:startDate endDate:endDate options:HKQueryOptionStrictStartDate];
    
    HKCorrelationQuery *query = [[HKCorrelationQuery alloc] initWithType:type predicate:predicate samplePredicates:nil completion:^(HKCorrelationQuery *query, NSArray *correlations, NSError *error) {
                        if (error) {
                                            dispatch_sync(dispatch_get_main_queue(), ^{
                                                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                                                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                                            });
                                        } else {
                                            
                                            NSDateFormatter *df = [[NSDateFormatter alloc] init];
                                            [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                                            
                                            
                                            NSMutableArray *finalResults = [[NSMutableArray alloc] initWithCapacity:correlations.count];
                                            
                                            for (HKSample *sample in correlations) {
                                                
                                                NSDate *startSample = sample.startDate;
                                                NSDate *endSample = sample.endDate;
                                                
                                                NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                                              [df stringFromDate:startSample], HKSampleKeyStartDate,
                                                                              [df stringFromDate:endSample], HKSampleKeyEndDate,
                                                                              nil];
                                                
                                                if ([sample isKindOfClass:[HKCategorySample class]]) {
                                                    HKCategorySample *csample = (HKCategorySample *)sample;
                                                    [entry setValue:[NSNumber numberWithLong:csample.value] forKey:@"value"];
                                                    [entry setValue:csample.categoryType.identifier forKey:@"catagoryType.identifier"];
                                                    [entry setValue:csample.categoryType.description forKey:@"catagoryType.description"];
                                                } else if ([sample isKindOfClass:[HKCorrelation class]]) {
                                                    HKCorrelation* correlation = (HKCorrelation*)sample;
                                                    [entry setValue:correlation.correlationType.identifier forKey:HKSampleKeyCorrelationType];
                                                    [entry setValue:correlation.metadata != nil ? correlation.metadata : @{} forKey:HKSampleKeyMetadata];
                                                    [entry setValue:correlation.UUID.UUIDString forKey:HKSampleKeyUUID];
                                                    NSMutableArray* samples = [NSMutableArray array];
                                                    for (HKQuantitySample* sample in correlation.objects) {
                                                        [samples addObject:@{HKSampleKeyStartDate:[df stringFromDate:sample.startDate],HKSampleKeyEndDate:[df stringFromDate:sample.endDate],HKSampleKeySampleType:sample.sampleType.identifier,HKSampleKeyValue:[NSNumber numberWithDouble:[sample.quantity doubleValueForUnit:unit]],HKSampleKeyUnit:unit.unitString,HKSampleKeyMetadata:sample.metadata != nil ? sample.metadata : @{},HKSampleKeyUUID:sample.UUID.UUIDString}];
                                                    }
                                                    [entry setValue:samples forKey:HKSampleKeyObjects];
                                                    // TODO
                                                } else if ([sample isKindOfClass:[HKQuantitySample class]]) {
                                                    HKQuantitySample *qsample = (HKQuantitySample *)sample;
                                                    // TODO compare with unit
                                                    [entry setValue:[NSNumber numberWithDouble:[qsample.quantity doubleValueForUnit:unit]] forKey:@"quantity"];
                                                    
                                                } else if ([sample isKindOfClass:[HKCorrelationType class]]) {
                                                    // TODO
                                                } else if ([sample isKindOfClass:[HKWorkout class]]) {
                                                    HKWorkout *wsample = (HKWorkout*)sample;
                                                    [entry setValue:[NSNumber numberWithDouble:wsample.duration] forKey:@"duration"];
                                                }
                                                
                                                [finalResults addObject:entry];
                                            }
                                            
                                            dispatch_sync(dispatch_get_main_queue(), ^{
                                                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:finalResults];
                                                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
                                            });
                                        }
                                    }];
            
    [self.healthStore executeQuery:query];
}

- (void) saveQuantitySample:(CDVInvokedUrlCommand*)command {
    NSMutableDictionary *args = [command.arguments objectAtIndex:0];
    
    //Use helper method to create quantity sample
    NSError* error = nil;
    HKQuantitySample *sample = [self loadHKQuantitySampleFromInputDictionary:args error:&error];
    
    //If error in creation, return plugin result
    if (error) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
    
    //Otherwise save to health store
    [self.healthStore saveObject:sample withCompletion:^(BOOL success, NSError *error) {
        if (success) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            });
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            });
        }
    }];

}

- (void) saveCorrelation:(CDVInvokedUrlCommand*)command {
    NSMutableDictionary *args = [command.arguments objectAtIndex:0];
    NSError* error = nil;
    
    //Use helper method to create correlation
    HKCorrelation *correlation = [self loadHKCorrelationFromInputDictionary:args error:&error];
    
    //If error in creation, return plugin result
    if (error) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
    
    //Otherwise save to health store
    [self.healthStore saveObject:correlation withCompletion:^(BOOL success, NSError *error) {
        if (success) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            });
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            });
        }
    }];
}


#pragma mark - helper methods
- (HKUnit*) getUnit:(NSString*) type : (NSString*) expected {
  HKUnit *localUnit;
  @try {
    localUnit = [HKUnit unitFromString:type];
    if ([[[localUnit class] description] isEqualToString:expected]) {
      return localUnit;
    } else {
      return nil;
    }
  }
  @catch(NSException *e) {
    return nil;
  }
}

- (HKObjectType*) getHKObjectType:(NSString*) elem {
  HKObjectType *type = [HKObjectType quantityTypeForIdentifier:elem];
  if (type == nil) {
    type = [HKObjectType characteristicTypeForIdentifier:elem];
  }
  if (type == nil){
      type = [self getHKSampleType:elem];
  }
  return type;
}

- (HKQuantityType*) getHKQuantityType:(NSString*) elem {
    HKQuantityType *type = [HKQuantityType quantityTypeForIdentifier:elem];
    return type;
}

- (HKSampleType*) getHKSampleType:(NSString*) elem {
    HKSampleType *type = [HKObjectType quantityTypeForIdentifier:elem];
    if (type == nil) {
        type = [HKObjectType categoryTypeForIdentifier:elem];
    }
    if (type == nil) {
        type = [HKObjectType quantityTypeForIdentifier:elem];
    }
    if (type == nil) {
        type = [HKObjectType correlationTypeForIdentifier:elem];
    }
    if (type == nil && [elem isEqualToString:@"workoutType"]) {
        type = [HKObjectType workoutType];
    }
    return type;
}

//Helper to parse out a quantity sample from a dictionary and perform error checking
- (HKQuantitySample*) loadHKQuantitySampleFromInputDictionary:(NSDictionary*) inputDictionary error:(NSError**) error {
    //Load quantity sample from args to command
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyStartDate error:error])        return nil;
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[[inputDictionary objectForKey:HKSampleKeyStartDate] longValue]];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyEndDate error:error])        return nil;
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:[[inputDictionary objectForKey:HKSampleKeyEndDate] longValue]];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeySampleType error:error])        return nil;
    NSString *sampleTypeString = [inputDictionary objectForKey:HKSampleKeySampleType];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyUnit error:error])        return nil;
    NSString *unitString = [inputDictionary objectForKey:HKSampleKeyUnit];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyValue error:error])        return nil;
    double value = [[inputDictionary objectForKey:HKSampleKeyValue] doubleValue];
    
    //Load optional metadata key
    NSDictionary* metadata = [inputDictionary objectForKey:HKSampleKeyMetadata];
    if (metadata == nil)
        metadata = @{};
    
    return [self getHKQuantitySampleWithStartDate:startDate endDate:endDate sampleTypeString:sampleTypeString unitTypeString:unitString value:value metadata:metadata error:error];
}

//Helper to parse out a correlation from a dictionary and perform error checking
- (HKCorrelation*) loadHKCorrelationFromInputDictionary:(NSDictionary*) inputDictionary error:(NSError**) error {
    //Load correlation from args to command
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyStartDate error:error])        return nil;
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[[inputDictionary objectForKey:HKSampleKeyStartDate] longValue]];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyEndDate error:error])        return nil;
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:[[inputDictionary objectForKey:HKSampleKeyEndDate] longValue]];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyCorrelationType error:error])        return nil;
    NSString *correlationTypeString = [inputDictionary objectForKey:HKSampleKeyCorrelationType];
    
    if (![self inputDictionary:inputDictionary hasRequiredKey:HKSampleKeyObjects error:error])        return nil;
    NSArray* objectDictionaries = [inputDictionary objectForKey:HKSampleKeyObjects];
    
    NSMutableSet* objects = [NSMutableSet set];
    for (NSDictionary* objectDictionary in objectDictionaries) {
        HKQuantitySample* sample = [self loadHKQuantitySampleFromInputDictionary:objectDictionary error:error];
        if (sample == nil)
            return nil;
        [objects addObject:sample];
    }
    NSDictionary *metadata = [inputDictionary objectForKey:HKSampleKeyMetadata];
    if (metadata == nil)
        metadata = @{};
    return [self getHKCorrelationWithStartDate:startDate endDate:endDate correlationTypeString:correlationTypeString objects:objects metadata:metadata error:error];
}

//Helper to isolate error checking on inputs for plugin
-(BOOL) inputDictionary:(NSDictionary*) inputDictionary hasRequiredKey:(NSString*) key error:(NSError**) error {
    if ([inputDictionary objectForKey:HKSampleKeyStartDate] == nil){
        *error = [NSError errorWithDomain:nil code:0 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"required value -%@- was missing from dictionary %@",HKSampleKeyStartDate,[inputDictionary description]]}];
        return false;
    }
    return true;
}

// Helper to handle the functionality with HealthKit to get a quantity sample
- (HKQuantitySample*) getHKQuantitySampleWithStartDate:(NSDate*) startDate endDate:(NSDate*) endDate sampleTypeString:(NSString*) sampleTypeString unitTypeString:(NSString*) unitTypeString value:(double) value metadata:(NSDictionary*) metadata error:(NSError**) error {
    HKQuantityType *type = [self getHKQuantityType:sampleTypeString];
    if (type==nil) {
        *error = [NSError errorWithDomain:nil code:0 userInfo:@{NSLocalizedDescriptionKey:@"quantity type string was invalid"}];
        return nil;
    }
    HKUnit *unit = unitTypeString!=nil ? [HKUnit unitFromString:unitTypeString] : nil;
    if (unit==nil) {
        *error = [NSError errorWithDomain:nil code:0 userInfo:@{NSLocalizedDescriptionKey:@"unit was invalid"}];
        return nil;
    }
    HKQuantity *quantity = [HKQuantity quantityWithUnit:unit doubleValue:value];
    if (![quantity isCompatibleWithUnit:unit]) {
        *error = [NSError errorWithDomain:nil code:0 userInfo:@{NSLocalizedDescriptionKey:@"unit was not compatible with quantity"}];
        return nil;
    }
    
    return [HKQuantitySample quantitySampleWithType:type quantity:quantity startDate:startDate endDate:endDate metadata:metadata];
}

- (HKCorrelation*) getHKCorrelationWithStartDate:(NSDate*) startDate endDate:(NSDate*) endDate correlationTypeString:(NSString*) correlationTypeString objects:(NSSet*) objects metadata:(NSDictionary*) metadata error:(NSError**) error {
    NSLog(@"correlation type is %@",HKCorrelationTypeIdentifierBloodPressure);
    HKCorrelationType *correlationType = [HKCorrelationType correlationTypeForIdentifier:correlationTypeString];
    if (correlationType == nil) {
        *error = [NSError errorWithDomain:nil code:0 userInfo:@{NSLocalizedDescriptionKey:@"correlation type string was invalid"}];
        return nil;
    }
    return [HKCorrelation correlationWithType:correlationType startDate:startDate endDate:endDate objects:objects metadata:metadata];
}
@end
