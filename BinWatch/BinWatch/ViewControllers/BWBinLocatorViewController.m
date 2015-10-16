//
//  BWBinLocatorViewController.m
//  BinWatch
//
//  Created by Supritha Nagesha on 03/09/15.
//  Copyright (c) 2015 Airwatch. All rights reserved.
//

#import "BWBinLocatorViewController.h"
#import "SPGooglePlacesAutocomplete.h"
#import "BWDataHandler.h"
#import "BWBin.h"
#import "BWLogger.h"
#import "BWHelpers.h"
#import "BWAppSettings.h"
#import "BWConstants.h"

#define DEFAULT_ZOOM_LEVEL 15


@interface BWBinLocatorViewController () <GMSMapViewDelegate>

@property (strong, nonatomic) IBOutlet UISearchBar *mapSearchBar;

@end

@implementation BWBinLocatorViewController
{
    GMSMapView *mapView;
    BOOL firstLocationUpdate_;
    float zoomLevel;
    NSMutableDictionary *mapMarkers;
    CLLocation *currentLocation;
    NSMutableArray *selectedLocations;
    BOOL isMapEdited;
    BWSettingsControl *settingsControl;
}

#pragma mark - View Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];

    zoomLevel = DEFAULT_ZOOM_LEVEL;
    firstLocationUpdate_ = NO;
    isMapEdited = NO;

    mapMarkers = [[NSMutableDictionary alloc] init];
    currentLocation = [[CLLocation alloc] init];
    selectedLocations = [[NSMutableArray alloc] init];

    // Navigation Bar Init
    UIBarButtonItem *moreButton = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:kMoreButtonImageName] style:UIBarButtonItemStyleDone target:self action:@selector(moreTapped)];
    self.navigationItem.rightBarButtonItem = moreButton;

    // Register for orientation change
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceOrientationDidChangeNotification:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    
    [[BWRoute sharedInstance] setDelegate:self];
    
    searchQuery = [[SPGooglePlacesAutocompleteQuery alloc] initWithApiKey:kGoogleAPIKey_Browser];
    shouldBeginEditing = YES;

    // UISearchBar Init
    self.searchDisplayController.searchBar.placeholder = kSearchPlaceHolder;
    [self.mapSearchBar setBackgroundImage:[[UIImage alloc]init]];
    [self.mapSearchBar setTranslucent:NO];

    // Bangalore MG Road
    GMSCameraPosition *camera = [GMSCameraPosition cameraWithLatitude:12.9667
                                                            longitude:77.5667
                                                                 zoom:zoomLevel];

    mapView = [GMSMapView mapWithFrame:CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height) camera:camera];
    // TODO: Give an option for hybrid view
    //mapView.mapType = kGMSTypeHybrid;
    [self resizeMapView];
    mapView.delegate = self;

    [self drawBins];
    
    mapView.settings.compassButton = YES;
    mapView.settings.myLocationButton = YES;
    mapView.trafficEnabled = YES;
    mapView.buildingsEnabled = YES;
    // TODO: Does this help?
    //mapView.indoorEnabled = YES;
    [mapView addObserver:self
              forKeyPath:@"myLocation"
                 options:NSKeyValueObservingOptionNew
                 context:NULL];
    
    // Ask for My Location data after the map has already been added to the UI.
    dispatch_async(dispatch_get_main_queue(), ^{
        mapView.myLocationEnabled = YES;
    });
    
    [self.view addSubview:mapView];
    [self.view bringSubviewToFront:_mapSearchBar];
    
    settingsControl = [[BWSettingsControl alloc] init];
    NSString *switchTo;
    if([BWAppSettings sharedInstance].appMode == BWBBMP)
        switchTo = kSwitchToUser;
    else
        switchTo = kSwitchToBBMP;
    
    [settingsControl createMenuInViewController:self withCells:@[@"Route to all Red bins", @"Route to all Red/Yellow bins", @"Route to selected bins", kSettings, kExport, kReportAnIssue, switchTo] andWidth:200];
    [settingsControl setDelegate:self];

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    [mapView removeObserver:self
                 forKeyPath:@"myLocation"
                    context:NULL];
}

#pragma mark - Event Handlers
- (void)moreTapped
{
    [settingsControl toggleControl];

    NSLog(@"More tapped");
    //[self drawRouteSelectedBins];
}

#pragma mark - Map Utils
- (void) resizeMapView
{
    [mapView setFrame:CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height - self.tabBarController.tabBar.frame.size.height)];

    // TODO: Whats this 10? No idea...
    //[mapView setFrame:CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y + self.tabBarController.tabBar.frame.size.height + self.searchDisplayController.searchBar.frame.size.height + 10, self.view.frame.size.width, self.view.frame.size.height - (self.tabBarController.tabBar.frame.size.height * 2) - self.searchDisplayController.searchBar.frame.size.height - 10)];
}

-(void) flushAllRoutes
{
    [mapView clear];
    [self drawBins];
}

-(void) drawRouteSelectedBins
{
    if(selectedLocations.count <= 0)
    {
        [self flushAllRoutes];
        [BWLogger DoLog:@"No bins are selected"];
        [BWHelpers displayHud:kNoSelectedBins onView:self.navigationController.view];
        return;
    }
    // TODO: Hardcoded for testing
    //currentLocation = [[CLLocation alloc] initWithLatitude:12.927991 longitude:77.60381700000001];
    if(currentLocation.coordinate.longitude == 0 || currentLocation.coordinate.latitude == 0)
    {
        [self flushAllRoutes];
        [BWLogger DoLog:@"Couldnt retrieve current location"];
        [BWHelpers displayHud:kCurrentLocationFailed onView:self.navigationController.view];
        return;
    }
    
    NSMutableArray *locations = [[NSMutableArray alloc] init];
    
    // Adding current locations
    [locations addObject:currentLocation];
    
    for(int iter = 0; iter < selectedLocations.count; iter++)
    {
        [locations addObject:[selectedLocations objectAtIndex:iter]];
    }
    [[BWRoute sharedInstance] fetchRoute:locations travelMode:TravelModeDriving];
}

-(void) drawRouteAllReds
{
    // TODO: Hardcoded for testing
    //currentLocation = [[CLLocation alloc] initWithLatitude:12.927991 longitude:77.60381700000001];
    if(currentLocation.coordinate.longitude == 0 || currentLocation.coordinate.latitude == 0)
    {
        [self flushAllRoutes];
        [BWLogger DoLog:@"Couldnt retrieve current location"];
        [BWHelpers displayHud:kCurrentLocationFailed onView:self.navigationController.view];
        return;
    }

    NSMutableArray *locations = [[NSMutableArray alloc] init];

    // Adding current locations
    [locations addObject:currentLocation];
    NSMutableArray *bins = [[[BWDataHandler sharedHandler] fetchBins] mutableCopy];

    for(int iter = 0; iter < bins.count; iter++)
    {
        BWBin *bin = [bins objectAtIndex:iter];
        if(bin.fill.floatValue > RED_BOUNDARY)
            [locations addObject:[[CLLocation alloc] initWithLatitude:bin.latitude.floatValue longitude:bin.longitude.floatValue]];
    }
    [[BWRoute sharedInstance] fetchRoute:locations travelMode:TravelModeDriving];
}

-(void) drawRouteRedYellow
{
    //currentLocation = [[CLLocation alloc] initWithLatitude:12.927991 longitude:77.60381700000001];
    if(currentLocation.coordinate.longitude == 0 || currentLocation.coordinate.latitude == 0)
    {
        [self flushAllRoutes];
        [BWLogger DoLog:@"Couldnt retrieve current location"];
        [BWHelpers displayHud:kCurrentLocationFailed onView:self.navigationController.view];
        return;
    }
    
    NSMutableArray *locations = [[NSMutableArray alloc] init];
    
    // Adding current locations
    [locations addObject:currentLocation];
    NSMutableArray *bins = [[[BWDataHandler sharedHandler] fetchBins] mutableCopy];
    
    for(int iter = 0; iter < bins.count; iter++)
    {
        BWBin *bin = [bins objectAtIndex:iter];
        if(bin.fill.floatValue > YELLOW_BOUNDARY)
            [locations addObject:[[CLLocation alloc] initWithLatitude:bin.latitude.floatValue longitude:bin.longitude.floatValue]];
    }
    [[BWRoute sharedInstance] fetchRoute:locations travelMode:TravelModeDriving];
}


-(void) drawBins
{
    NSMutableArray *bins = [[[BWDataHandler sharedHandler] fetchBins] mutableCopy];
    int noOfBins = bins.count;
    
    for(int iter = 0; iter < noOfBins; iter++)
    {
        BWBin *bin = [bins objectAtIndex:iter];
        GMSMarker *marker = [[GMSMarker alloc] init];
        marker.position = CLLocationCoordinate2DMake(bin.latitude.floatValue, bin.longitude.floatValue);
        marker.appearAnimation = kGMSMarkerAnimationPop;
        marker.title = bin.place;

        NSDictionary *binData = [self getIconAndDataFor:bin];
        marker.icon = [binData objectForKey:kIcon];
        marker.userData = [binData objectForKey:kUserData];
        marker.map = mapView;
        
        // TODO: is there a better alternative for this? Objective C equivalent of C struct
        NSMutableArray *arr = [[NSMutableArray alloc] init];
        [arr addObject:bin];
        [arr addObject:marker];
        
        [mapMarkers setValue:arr forKey:bin.binID];
    }
    //[self drawRoute];
}

-(void) resetBinIcons
{
    NSArray *allKeys = [mapMarkers allKeys];
    for(NSString *uniqueId in allKeys)
    {
        NSArray *item = [mapMarkers objectForKey:uniqueId];
        BWBin *obj = item[0];
        GMSMarker *marker = item[1];
        marker.icon = [self getIconFor:obj.color];
    }
}

-(NSDictionary *) getIconAndDataFor:(BWBin *) bin
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    NSInteger binColor = [bin.color integerValue];

    switch(binColor)
    {
        case BWYellow:
            [dict setValue:[UIImage imageNamed:kTrashYellow] forKey:kIcon];
            [dict setValue:kYellow forKey:kUserData];
            return dict;

        case BWRed:
            [dict setValue:[UIImage imageNamed:kTrashRed] forKey:kIcon];
            [dict setValue:kRed forKey:kUserData];
            return dict;

        case BWGreen:
            [dict setValue:[UIImage imageNamed:kTrashGreen] forKey:kIcon];
            [dict setValue:kGreen forKey:kUserData];
            return dict;

        default:
            // TODO:
            return nil;
    }
}

-(UIImage *) getIconFor:(NSNumber *) binC
{
    NSInteger binColor = [binC integerValue];
    switch(binColor)
    {
        case BWYellow:
            return [UIImage imageNamed:@"trashYellow"];
        case BWRed:
            return [UIImage imageNamed:@"trashRed"];
        case BWGreen:
            return [UIImage imageNamed:@"trashGreen"];
        default:
            // TODO:
            return nil;
    }
}

#pragma mark - KVO updates
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    NSLog(@"Location Update");
    //CLLocation *location;
    currentLocation = [change objectForKey:NSKeyValueChangeNewKey];
    if (!firstLocationUpdate_) {
        // If the first location update has not yet been recieved, then jump to that
        // location.
        firstLocationUpdate_ = YES;
        mapView.camera = [GMSCameraPosition cameraWithTarget:currentLocation.coordinate
                                                        zoom:zoomLevel];
    }
    
    // TODO: Is this the correct place to do this?
    //currentLocation = [[CLLocation alloc] initWithLatitude:location.coordinate.latitude longitude:location.coordinate.longitude];
}

#pragma mark - GMSMapViewDelegates
- (void) mapView:(GMSMapView *)mapView didTapAtCoordinate:(CLLocationCoordinate2D)coordinate
{
    [settingsControl hideControl];
    NSLog(@"did tap at cordinate");
    if(!isMapEdited)
        return;

    //[self resetBinIcons];
    [selectedLocations removeAllObjects];
    [self flushAllRoutes];
    isMapEdited = NO;
}

/*
 Returns:
 YES if this delegate handled the tap event, which prevents the map from performing its default selection behavior, and NO if the map should continue with its default selection behavior.
 */
- (BOOL)mapView:(GMSMapView *)mapView didTapMarker:(GMSMarker *)marker
{
    [settingsControl hideControl];

    isMapEdited = YES;
    NSLog(@"did tap at marker - %f %f - %@", marker.position.latitude, marker.position.longitude, marker.title);

    if([marker.userData isEqualToString:kYellow])
        marker.icon = [UIImage imageNamed:kTrashPickerYellow];
    else if([marker.userData isEqualToString:kGreen])
        marker.icon = [UIImage imageNamed:kTrashPickerGreen];
    else if([marker.userData isEqualToString:kRed])
        marker.icon = [UIImage imageNamed:kTrashPickerRed];
    
    [selectedLocations addObject:[[CLLocation alloc] initWithLatitude:marker.position.latitude longitude:marker.position.longitude]];
    return NO;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [searchResultPlaces count];
}

- (SPGooglePlacesAutocompletePlace *)placeAtIndexPath:(NSIndexPath *)indexPath {
    return searchResultPlaces[indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"SPGooglePlacesAutocompleteCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    cell.textLabel.font = [UIFont fontWithName:@"GillSans" size:16.0];
    cell.textLabel.text = [self placeAtIndexPath:indexPath].name;
    return cell;
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)recenterMapToPlacemark:(CLPlacemark *)placemark {
    
    GMSCameraPosition *newPosition = [GMSCameraPosition cameraWithLatitude:placemark.location.coordinate.latitude
                                                            longitude:placemark.location.coordinate.longitude
                                                                 zoom:zoomLevel];
    [mapView animateToCameraPosition:newPosition];
}

//- (void)addPlacemarkAnnotationToMap:(CLPlacemark *)placemark addressString:(NSString *)address {
//    [self.mapView removeAnnotation:selectedPlaceAnnotation];
//
//    selectedPlaceAnnotation = [[MKPointAnnotation alloc] init];
//    selectedPlaceAnnotation.coordinate = placemark.location.coordinate;
//    selectedPlaceAnnotation.title = address;
//    [self.mapView addAnnotation:selectedPlaceAnnotation];
//}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SPGooglePlacesAutocompletePlace *place = [self placeAtIndexPath:indexPath];
    [place resolveToPlacemark:^(CLPlacemark *placemark, NSString *addressString, NSError *error) {
        if (error) {
            [BWLogger DoLog:@"Could not map selected Place"];
            [BWHelpers displayHud:kSelectedPlaceFetchFailed onView:self.navigationController.view];
        } else if (placemark) {
            //[self addPlacemarkAnnotationToMap:placemark addressString:addressString];
            [self recenterMapToPlacemark:placemark];
            // ref: https://github.com/chenyuan/SPGooglePlacesAutocomplete/issues/10
            [self.searchDisplayController setActive:NO];
            [self.searchDisplayController.searchResultsTableView deselectRowAtIndexPath:indexPath animated:NO];
        }
    }];
}

#pragma mark - UISearchDisplayDelegate

- (void)handleSearchForSearchString:(NSString *)searchString {
    //searchQuery.location = self.mapView.userLocation.coordinate;
    // TODO: This has to be corrected
    searchQuery.location = CLLocationCoordinate2DMake(12.9898231, 77.7148933);
    searchQuery.input = searchString;
    [searchQuery fetchPlaces:^(NSArray *places, NSError *error) {
        if (error) {
            [BWLogger DoLog:@"Could not fetch Places"];
            [BWHelpers displayHud:kPlacesFetchFailed onView:self.navigationController.view];
        } else {
            searchResultPlaces = places;
            [self.searchDisplayController.searchResultsTableView reloadData];
        }
    }];
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString {
    [self handleSearchForSearchString:searchString];
    
    // Return YES to cause the search result table view to be reloaded.
    return YES;
}

#pragma mark - UISearchBar Delegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (![searchBar isFirstResponder]) {
        // User tapped the 'clear' button.
        shouldBeginEditing = NO;
        [self.searchDisplayController setActive:NO];
        //[self.mapView removeAnnotation:selectedPlaceAnnotation];
    }
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
    if (shouldBeginEditing) {
        // Animate in the table view.
        NSTimeInterval animationDuration = 0.3;
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:animationDuration];
        self.searchDisplayController.searchResultsTableView.alpha = 0.75;
        [UIView commitAnimations];
        
        [self.searchDisplayController.searchBar setShowsCancelButton:YES animated:YES];
    }
    BOOL boolToReturn = shouldBeginEditing;
    shouldBeginEditing = YES;
    return boolToReturn;
}

// TODO: Can I do this using auto resize masks?
- (void)deviceOrientationDidChangeNotification:(NSNotification*)note
{
    [self resizeMapView];
}

#pragma mark - RouteFetchDelegate

- (void)routeFetchFailedWithError:(NSError *)error
{
    [BWLogger DoLog:@"Route Fetch failed"];
    [BWHelpers displayHud:kRouteFetchFailed onView:self.navigationController.view];
}

- (void)routeFetchDidReceiveResponse:(NSString *)points
{
    GMSPath *path = [GMSPath pathFromEncodedPath:points];
    GMSPolyline *polyline = [GMSPolyline polylineWithPath:path];
    polyline.strokeWidth = 5.f;
    polyline.strokeColor = [UIColor blackColor];
    polyline.map = mapView;
    isMapEdited = YES;
}

#pragma mark - BWSettingsControlDelegate

- (void)didTapSettingsRow:(NSInteger)row
{
    NSLog(@"Tapped : %d", (int)row);
    int rowIndex = (int)row;
    switch (rowIndex) {
        case 0:
            [self drawRouteAllReds];
            break;
        case 1:
            [self drawRouteRedYellow];
            break;
        case 2:
            [self drawRouteSelectedBins];
            break;
        case 3:
            [BWHelpers displayHud:@"TODO" onView:self.navigationController.view];
            break;
        case 4:
            [BWHelpers displayHud:@"TODO" onView:self.navigationController.view];
            break;
        case 5:
            [BWHelpers displayHud:@"TODO" onView:self.navigationController.view];
            break;
        case 6:
            [BWHelpers displayHud:@"TODO" onView:self.navigationController.view];
            break;
            
        default:
            break;
    }
}

@end
