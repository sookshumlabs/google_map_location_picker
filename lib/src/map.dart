import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:geolocator/geolocator.dart' as geoLocator;
import 'package:geolocator/geolocator.dart';

import 'package:google_map_location_picker/generated/l10n.dart';
import 'package:google_map_location_picker/src/providers/location_provider.dart';
import 'package:google_map_location_picker/src/slider.dart';
import 'package:google_map_location_picker/src/utils/loading_builder.dart';
import 'package:google_map_location_picker/src/utils/log.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'utils/location_utils.dart';

class MapPicker extends StatefulWidget {
  const MapPicker(
    this.apiKey, {
    Key key,
    this.initialCenter,
    this.initialZoom,
    this.requiredGPS,
    this.myLocationButtonEnabled,
    this.layersButtonEnabled,
    this.automaticallyAnimateToCurrentLocation,
    this.mapStylePath,
    this.appBarColor,
    this.searchBarBoxDecoration,
    this.hintText,
    this.resultCardConfirmIcon,
    this.resultCardAlignment,
    this.resultCardDecoration,
    this.resultCardPadding,
    this.language,
    this.existingLocationName,
    this.geofenceRadius,
    this.locationPickerType,
  }) : super(key: key);

  final String apiKey;

  final LatLng initialCenter;
  final double initialZoom;

  final bool requiredGPS;
  final bool myLocationButtonEnabled;
  final bool layersButtonEnabled;
  final bool automaticallyAnimateToCurrentLocation;

  final String mapStylePath;

  final Color appBarColor;
  final BoxDecoration searchBarBoxDecoration;
  final String hintText;
  final Widget resultCardConfirmIcon;
  final Alignment resultCardAlignment;
  final Decoration resultCardDecoration;
  final EdgeInsets resultCardPadding;

  final String language;
  final dynamic locationPickerType;
  final dynamic existingLocationName;
  final dynamic geofenceRadius;
  @override
  MapPickerState createState() => MapPickerState();
}

class MapPickerState extends State<MapPicker> {
  Completer<GoogleMapController> mapController = Completer();

  MapType _currentMapType = MapType.normal;

  String _mapStyle;

  LatLng _lastMapPosition;

  Position _currentPosition;

  String _address;

  String _placeId;

  double radius = 150;

  void _onToggleMapTypePressed() {
    final MapType nextType = MapType.values[(_currentMapType.index + 1) % MapType.values.length];

    setState(() => _currentMapType = nextType);
  }

  // this also checks for location permission.
  Future<void> _initCurrentLocation() async {
    Position currentPosition;
    try {
      currentPosition = await Geolocator.getCurrentPosition();
      d("position = $currentPosition");

      setState(() => _currentPosition = currentPosition);
    } catch (e) {
      currentPosition = null;
      d("_initCurrentLocation#e = $e");
    }

    if (!mounted) return;

    setState(() => _currentPosition = currentPosition);

    if (currentPosition != null)
      moveToCurrentLocation(LatLng(currentPosition.latitude, currentPosition.longitude));
  }

  Future moveToCurrentLocation(LatLng currentLocation) async {
    d('MapPickerState.moveToCurrentLocation "currentLocation = [$currentLocation]"');
    final controller = await mapController.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: currentLocation, zoom: 16),
    ));
  }

  @override
  void initState() {
    super.initState();
    if (widget.automaticallyAnimateToCurrentLocation && !widget.requiredGPS) _initCurrentLocation();

    if (widget.mapStylePath != null) {
      rootBundle.loadString(widget.mapStylePath).then((string) {
        _mapStyle = string;
      });
    }
    if (widget.locationPickerType == 'update') {
      setState(() {
        radius = widget.geofenceRadius ?? 150;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requiredGPS) {
      _checkGeolocationPermission();
      if (_currentPosition == null) _initCurrentLocation();
    }

    if (_currentPosition != null && dialogOpen != null)
      Navigator.of(context, rootNavigator: true).pop();

    return Scaffold(
      body: Builder(
        builder: (context) {
          if (_currentPosition == null &&
              widget.automaticallyAnimateToCurrentLocation &&
              widget.requiredGPS) {
            return const Center(child: CircularProgressIndicator());
          }

          return buildMap();
        },
      ),
    );
  }

  Set<Circle> _circles = HashSet<Circle>();
//ids
  int _circleIdCounter = 1;
  dynamic locationReminderAt = '';

  // Set circles as points to the map
  void _setCircles(LatLng point) {
    final String circleIdVal = 'circle_id_$_circleIdCounter';
    _circleIdCounter++;
    setState(() {
      _circles.clear();
      _circles.add(
        Circle(
          circleId: CircleId(circleIdVal),
          center: point,
          radius: radius,
          fillColor: Color(0xFFB3B2B280),
          strokeWidth: 3,
          strokeColor: Color(0xFFB3B2B2),
        ),
      );
    });
  }

  Widget buildMap() {
    return Center(
      child: Stack(
        children: <Widget>[
          GoogleMap(
            myLocationButtonEnabled: false,
            initialCameraPosition: CameraPosition(
              target: widget.initialCenter,
              zoom: widget.initialZoom,
            ),
            onMapCreated: (GoogleMapController controller) {
              mapController.complete(controller);

              //Implementation of mapStyle
              if (widget.mapStylePath != null) {
                controller.setMapStyle(_mapStyle);
              }

              _lastMapPosition = widget.initialCenter;
              LocationProvider.of(context, listen: false).setLastIdleLocation(_lastMapPosition);
            },
            onCameraMove: (CameraPosition position) {
              _lastMapPosition = position.target;
            },
            onCameraIdle: () async {
              print("onCameraIdle#_lastMapPosition = $_lastMapPosition");

              LocationProvider.of(context, listen: false).setLastIdleLocation(_lastMapPosition);
              _setCircles(_lastMapPosition);
            },
            onCameraMoveStarted: () {
              print("onCameraMoveStarted#_lastMapPosition = $_lastMapPosition");
            },
            mapType: _currentMapType,
            circles: _circles,
            myLocationEnabled: true,
          ),
          pin(),
          // geoFenceReminderAtCard(),
          locationCard(),
        ],
      ),
    );
  }

  Widget geoFenceReminderAtCard() {
    return Positioned(bottom: 115.0, left: 5, right: 5, child: geoFenceReminderAt());
  }

  Key locationCardKey = Key('locationKey');
  Color primaryColor = Color(0xFF003A86);
  bool showRadiusSlider = false;
  double height = 250;
  double _defaultHight = 250;
  double _expandedHeight = 450;

  Widget locationCard() {
    return Align(
      alignment: widget.resultCardAlignment ?? Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          minHeight: 100,
          maxHeight: height,
          minWidth: MediaQuery.of(context).size.width,
        ),
        decoration: BoxDecoration(
          // color: Theme.of(context).cardTheme.color,
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).cardColor
              : Color(0xFFF9FAFA),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 12.0,
              offset: Offset(0, 3),
              color: Color(0xFF214A8119),
            ),
          ],
        ),
        width: MediaQuery.of(context).size.width,
        child: Consumer<LocationProvider>(
          builder: (context, locationProvider, _) {
            return Padding(
              padding: const EdgeInsets.only(top: 5.0, left: 10, right: 10, bottom: 5),
              child: Column(
                // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  FutureLoadingBuilder<Map<String, String>>(
                    future: getAddress(locationProvider.lastIdleLocation),
                    mutable: true,
                    loadingIndicator: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(height: 10),
                        CircularProgressIndicator(),
                      ],
                    ),
                    builder: (context, data) {
                      _address = data["address"];
                      _placeId = data["placeId"];
                      return Container(
                        decoration: BoxDecoration(
                          // color: Color(0xFFF9FAFA),
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).cardColor
                              : Color(0xFFF9FAFA),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        margin: EdgeInsets.all(10),
                        padding: EdgeInsets.all(10),
                        child: Container(
                          child: Text(
                            _address ?? S.of(context)?.unnamedPlace ?? 'Unnamed place',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Mulish',
                              fontWeight: FontWeight.w600,
                            ),
                            softWrap: true,
                            maxLines: 2,
                            // overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                  Spacer(),
                  Divider(
                    height: 10,
                  ),
                  Container(
                    margin: EdgeInsets.only(left: 20, right: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Radius',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'mulish',
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            setState(() {
                              showRadiusSlider = !showRadiusSlider;
                              height = !showRadiusSlider ? _defaultHight : _expandedHeight;
                            });
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              //Text( reminderAt.reduce((String value, element) => value + ',' + element.toString()), style:TextStyle(color:_textColor)),
                              Container(
                                alignment: Alignment.bottomRight,
                                padding: EdgeInsets.only(bottom: 5),
                                width: MediaQuery.of(context).size.width * 0.45,
                                child: Text(
                                  radius.round().toString() + ' m',
                                  style: TextStyle(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white
                                        : primaryColor,
                                    fontFamily: 'mulish',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),

                              Icon(
                                showRadiusSlider
                                    ? Icons.arrow_drop_up_sharp
                                    : Icons.arrow_drop_down_sharp,
                                size: 24,
                                color: primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showRadiusSlider) ...[
                    // radiusSlider()
                    Container(
                      decoration: BoxDecoration(
                        // color: Color(0xFFF9FAFA),
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).cardColor
                            : Color(0xFFF9FAFA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: EdgeInsets.all(10),
                      padding: EdgeInsets.all(5),
                      width: MediaQuery.of(context).size.width,
                      child: Container(
                        width: MediaQuery.of(context).size.width * .5,
                        child: Column(
                          children: [
                            Container(
                              width: MediaQuery.of(context).size.width,
                              child: ListTile(
                                title: Text(
                                  150.round().toString() + ' m',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: radius == 150.toDouble()
                                          ? primaryColor
                                          : Theme.of(context).textTheme.bodyText1.color),
                                ),
                                trailing: radius == 150.toDouble()
                                    ? Icon(
                                        Icons.done,
                                        color: primaryColor,
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    radius = 150;
                                    showRadiusSlider = !showRadiusSlider;
                                    height = !showRadiusSlider ? _defaultHight : _expandedHeight;
                                  });
                                  _setCircles(_lastMapPosition);
                                },
                              ),
                            ),
                            Container(
                              width: MediaQuery.of(context).size.width,
                              child: ListTile(
                                title: Text(
                                  200.round().toString() + ' m',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: radius == 200.toDouble()
                                        ? primaryColor
                                        : Theme.of(context).textTheme.bodyText1.color,
                                  ),
                                ),
                                trailing: radius == 200.toDouble()
                                    ? Icon(
                                        Icons.done,
                                        color: primaryColor,
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    radius = 200;
                                    showRadiusSlider = !showRadiusSlider;
                                    height = !showRadiusSlider ? _defaultHight : _expandedHeight;
                                  });
                                  _setCircles(_lastMapPosition);
                                },
                              ),
                            ),
                            Container(
                              width: MediaQuery.of(context).size.width,
                              child: ListTile(
                                title: Text(
                                  250.round().toString() + ' m',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: radius == 250.toDouble()
                                        ? primaryColor
                                        : Theme.of(context).textTheme.bodyText1.color,
                                  ),
                                ),
                                trailing: radius == 250.toDouble()
                                    ? Icon(
                                        Icons.done,
                                        color: primaryColor,
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    showRadiusSlider = !showRadiusSlider;
                                    radius = 250;
                                    height = !showRadiusSlider ? _defaultHight : _expandedHeight;
                                  });
                                  _setCircles(_lastMapPosition);
                                },
                              ),
                            ),
                            Container(
                              width: MediaQuery.of(context).size.width,
                              child: ListTile(
                                title: Text(
                                  300.round().toString() + 'm',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: radius == 300.toDouble()
                                        ? primaryColor
                                        : Theme.of(context).textTheme.bodyText1.color,
                                  ),
                                ),
                                trailing: radius == 300.toDouble()
                                    ? Icon(
                                        Icons.done,
                                        color: primaryColor,
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    radius = 300;
                                    showRadiusSlider = !showRadiusSlider;
                                    height = !showRadiusSlider ? _defaultHight : _expandedHeight;
                                  });
                                  _setCircles(_lastMapPosition);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!showRadiusSlider) ...[
                    SizedBox(
                      height: 20,
                    ),
                    Center(
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        padding: EdgeInsets.only(left: 10, right: 10, top: 0, bottom: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF0066B7),
                                Color(0xFF003A86),
                              ],
                            ),
                          ),
                          child: Container(
                            height: 50,
                            child: OutlineButton(
                              child: Text(
                                'Select Location',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Mulish',
                                  color: Colors.white,
                                ),
                              ),
                              onPressed: () async {
                                if (_address != null) {
                                  Navigator.of(context).pop({
                                    'location': {
                                      'latLng': LatLng(locationProvider.lastIdleLocation.latitude,
                                          locationProvider.lastIdleLocation.longitude),
                                      'address': "$_address",
                                      'notificationAt': locationReminderAt,
                                      'placeId': _placeId,
                                      'radius': radius
                                    },
                                  });
                                }
                              },
                              color: Color(0xFF76D4F4),
                              highlightedBorderColor: Colors.transparent,
                              borderSide: BorderSide(color: Colors.transparent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30.0),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(
                    height: 10,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<Map<String, String>> getAddress(LatLng location) async {
    try {
      final endPoint =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${location?.latitude},${location?.longitude}'
          '&key=${widget.apiKey}&language=${widget.language}';

      var response = jsonDecode(
          (await http.get(Uri.parse(endPoint), headers: await LocationUtils.getAppHeaders())).body);

      return {
        "placeId": response['results'][0]['place_id'],
        "address": response['results'][0]['formatted_address']
      };
    } catch (e) {
      print(e);
    }

    return {"placeId": null, "address": null};
  }

  Widget pin() {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.location_on,
              size: 40,
              color: Color(0xFF76D4F4),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF175EBA),
                border: Border.all(
                  color: Colors.white,
                  width: 1,
                ),
              ),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget radiusSlider() {
    return Container(
      margin: const EdgeInsets.only(top: 10, left: 15, right: 15),
      child: FluidSlider(
        min: 150,
        max: 300,
        sliderColor: primaryColor,
        textColor: Theme.of(context).textTheme.headline6.color,
        onValue: (value) {},
        onSlide: (value) {
          setState(() => radius = value.toDouble());
          _setCircles(_lastMapPosition);
        },
      ),
    );
  }

  Widget geoFenceReminderAt() {
    return Padding(
        padding: const EdgeInsets.all(5),
        child: Container(
          height: 50,
          width: MediaQuery.of(context).size.width,
          decoration: BoxDecoration(
              color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(5)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  child: FlatButton(
                onPressed: () {
                  setState(() => locationReminderAt = 'Leave: ');
                },
                child: Text(
                  'When I leave',
                  style: TextStyle(
                      color: locationReminderAt != 'Leave: '
                          ? Theme.of(context).textTheme.headline6.color.withOpacity(0.6)
                          : Theme.of(context).textTheme.headline6.color),
                ),
              )),
              Container(width: 1, height: 25, color: Colors.black),
              Container(
                  child: FlatButton(
                onPressed: () {
                  setState(() => locationReminderAt = 'Arrive: ');
                },
                child: Text(
                  'When I Arrive at',
                  style: TextStyle(
                      color: locationReminderAt != 'Arrive: '
                          ? Theme.of(context).textTheme.headline6.color.withOpacity(0.6)
                          : Theme.of(context).textTheme.headline6.color),
                ),
              )),
            ],
          ),
        ));
  }

  var dialogOpen;

  Future _checkGeolocationPermission() async {
    final geolocationStatus = await Geolocator.checkPermission();
    d("geolocationStatus = $geolocationStatus");

    if (geolocationStatus == LocationPermission.denied && dialogOpen == null) {
      dialogOpen = _showDeniedDialog();
    } else if (geolocationStatus == LocationPermission.deniedForever && dialogOpen == null) {
      dialogOpen = _showDeniedForeverDialog();
    } else if (geolocationStatus == LocationPermission.whileInUse ||
        geolocationStatus == LocationPermission.always) {
      d('GeolocationStatus.granted');

      if (dialogOpen != null) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = null;
      }
    }
  }

  Future _showDeniedDialog() {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async {
            Navigator.of(context, rootNavigator: true).pop();
            Navigator.of(context, rootNavigator: true).pop();
            return true;
          },
          child: AlertDialog(
            title: Text(S.of(context)?.access_to_location_denied ?? 'Access to location denied'),
            content: Text(S.of(context)?.allow_access_to_the_location_services ??
                'Allow access to the location services.'),
            actions: <Widget>[
              FlatButton(
                child: Text(S.of(context)?.ok ?? 'Ok'),
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  _initCurrentLocation();
                  dialogOpen = null;
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future _showDeniedForeverDialog() {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async {
            Navigator.of(context, rootNavigator: true).pop();
            Navigator.of(context, rootNavigator: true).pop();
            return true;
          },
          child: AlertDialog(
            title: Text(S.of(context)?.access_to_location_permanently_denied ??
                'Access to location permanently denied'),
            content: Text(S.of(context)?.allow_access_to_the_location_services_from_settings ??
                'Allow access to the location services for this App using the device settings.'),
            actions: <Widget>[
              FlatButton(
                child: Text(S.of(context)?.ok ?? 'Ok'),
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  Geolocator.openAppSettings();
                  dialogOpen = null;
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapFabs extends StatelessWidget {
  const _MapFabs({
    Key key,
    @required this.myLocationButtonEnabled,
    @required this.layersButtonEnabled,
    @required this.onToggleMapTypePressed,
    @required this.onMyLocationPressed,
  })  : assert(onToggleMapTypePressed != null),
        super(key: key);

  final bool myLocationButtonEnabled;
  final bool layersButtonEnabled;

  final VoidCallback onToggleMapTypePressed;
  final VoidCallback onMyLocationPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topRight,
      margin: const EdgeInsets.only(top: kToolbarHeight + 24, right: 8),
      child: Column(
        children: <Widget>[
          if (layersButtonEnabled)
            FloatingActionButton(
              onPressed: onToggleMapTypePressed,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              mini: true,
              child: Icon(Icons.layers, color: Theme.of(context).primaryColor),
              heroTag: "layers",
            ),
          if (myLocationButtonEnabled)
            FloatingActionButton(
              onPressed: onMyLocationPressed,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              mini: true,
              child: Icon(Icons.my_location, color: Theme.of(context).primaryColor),
              heroTag: "myLocation",
            ),
        ],
      ),
    );
  }
}
