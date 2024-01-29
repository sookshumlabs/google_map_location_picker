import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_map_location_picker/generated/l10n.dart';
import 'package:google_map_location_picker/src/map.dart';
import 'package:google_map_location_picker/src/providers/location_provider.dart';
import 'package:google_map_location_picker/src/rich_suggestion.dart';
import 'package:google_map_location_picker/src/search_input.dart';
import 'package:google_map_location_picker/src/utils/uuid.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'model/auto_complete_item.dart';
import 'model/location_result.dart';
import 'model/nearby_place.dart';
import 'utils/location_utils.dart';

class LocationPicker extends StatefulWidget {
  LocationPicker(
    this.apiKey, {
    Key? key,
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
    this.countries,
    this.desiredAccuracy,
    this.language = 'en',
    this.existingLocationName,
    this.geofenceRadius,
    this.locationPickerType,
  });

  final String apiKey;

  final LatLng? initialCenter;
  final double? initialZoom;
  final List<String>? countries;

  final bool? requiredGPS;
  final bool? myLocationButtonEnabled;
  final bool? layersButtonEnabled;
  final bool? automaticallyAnimateToCurrentLocation;

  final String? mapStylePath;

  final Color? appBarColor;
  final BoxDecoration? searchBarBoxDecoration;
  final String? hintText;
  final Widget? resultCardConfirmIcon;
  final Alignment? resultCardAlignment;
  final Decoration? resultCardDecoration;
  final EdgeInsets? resultCardPadding;

  final LocationAccuracy? desiredAccuracy;

  final String? language;
  final dynamic locationPickerType;
  final dynamic existingLocationName;
  final dynamic geofenceRadius;
  @override
  LocationPickerState createState() => LocationPickerState();
}

class LocationPickerState extends State<LocationPicker> {
  /// Result returned after user completes selection
  LocationResult? locationResult;

  /// Overlay to display autocomplete suggestions
  OverlayEntry? overlayEntry;

  List<NearbyPlace> nearbyPlaces = [];

  /// Session token required for autocomplete API call
  String sessionToken = Uuid().generateV4();

  var mapKey = GlobalKey<MapPickerState>();

  var appBarKey = GlobalKey();

  var searchInputKey = GlobalKey<SearchInputState>();

  bool hasSearchTerm = false;

  /// Hides the autocomplete overlay
  void clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry?.remove();
      overlayEntry = null;
    }
  }

  /// Begins the search process by displaying a "wait" overlay then
  /// proceeds to fetch the autocomplete list. The bottom "dialog"
  /// is hidden so as to give more room and better experience for the
  /// autocomplete list overlay.
  void searchPlace(String place) {
    if (context == null) return;

    clearOverlay();

    setState(() => hasSearchTerm = place.length > 0);
    if (place.length < 1) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    var size = renderBox!.size;

    final appBarBox = appBarKey.currentContext!.findRenderObject() as RenderBox?;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarBox?.size.height,
        width: size.width,
        child: Material(
          elevation: 1,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Finding place...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(.6),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry!);

    autoCompleteSearch(place);
  }

  /// Fetches the place autocomplete list with the query [place].
  void autoCompleteSearch(String place) {
    place = place.replaceAll(' ', '+');

    final countries = widget.countries;

    // Currently, you can use components to filter by up to 5 countries. from https://developers.google.com/places/web-service/autocomplete
    var regionParam = countries?.isNotEmpty == true
        ? "&components=country:${countries?.sublist(0, min(countries.length, 5)).join('|country:')}"
        : '';

    var endpoint = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?' +
        'key=${widget.apiKey}&' +
        'input={$place}$regionParam&sessiontoken=$sessionToken&' +
        'language=${widget.language}';

    if (locationResult != null) {
      endpoint +=
          '&location=${locationResult?.latLng?.latitude},' + '${locationResult?.latLng?.longitude}';
    }

    LocationUtils.getAppHeaders()
        .then((headers) => http.get(Uri.parse(endpoint), headers: headers))
        .then((response) {
      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        List<dynamic> predictions = data['predictions'];

        var suggestions = <RichSuggestion>[];

        if (predictions.isEmpty) {
          var aci = AutoCompleteItem();
          aci.text = S.of(context).no_result_found;
          aci.offset = 0;
          aci.length = 0;

          suggestions.add(RichSuggestion(aci, () {}));
        } else {
          for (dynamic t in predictions) {
            var aci = AutoCompleteItem();

            aci.id = t['place_id'];
            aci.text = t['description'];
            aci.offset = t['matched_substrings'][0]['offset'];
            aci.length = t['matched_substrings'][0]['length'];

            suggestions.add(RichSuggestion(aci, () {
              decodeAndSelectPlace(aci.id!);
            }));
          }
        }

        displayAutoCompleteSuggestions(suggestions);
      }
    }).catchError((dynamic error) {
      print(error);
    });
  }

  /// To navigate to the selected place from the autocomplete list to the map,
  /// the lat,lng is required. This method fetches the lat,lng of the place and
  /// proceeds to moving the map to that location.
  void decodeAndSelectPlace(String placeId) {
    clearOverlay();

    final endpoint =
        "https://maps.googleapis.com/maps/api/place/details/json?key=${widget.apiKey}" +
            "&placeid=$placeId" +
            '&language=${widget.language}';

    LocationUtils.getAppHeaders()
        .then((headers) => http.get(Uri.parse(endpoint), headers: headers))
        .then((response) {
      if (response.statusCode == 200) {
        Map<String, dynamic> location = jsonDecode(response.body)['result']['geometry']['location'];

        var latLng = LatLng(location['lat'], location['lng']);

        moveToLocation(latLng);
      }
    }).catchError((dynamic error) {
      print(error);
    });
  }

  /// Display autocomplete suggestions with the overlay.
  void displayAutoCompleteSuggestions(List<RichSuggestion> suggestions) {
    final renderBox = context.findRenderObject() as RenderBox?;
    var size = renderBox!.size;

    final appBarBox = appBarKey.currentContext!.findRenderObject() as RenderBox?;

    clearOverlay();

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        top: appBarBox?.size.height,
        child: Material(
          elevation: 1,
          child: Column(
            children: suggestions,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  /// Utility function to get clean readable name of a location. First checks
  /// for a human-readable name from the nearby list. This helps in the cases
  /// that the user selects from the nearby list (and expects to see that as a
  /// result, instead of road name). If no name is found from the nearby list,
  /// then the road name returned is used instead.
//  String getLocationName() {
//    if (locationResult == null) {
//      return "Unnamed location";
//    }
//
//    for (NearbyPlace np in nearbyPlaces) {
//      if (np.latLng == locationResult.latLng) {
//        locationResult.name = np.name;
//        return np.name;
//      }
//    }
//
//    return "${locationResult.name}, ${locationResult.locality}";
//  }

  /// Fetches and updates the nearby places to the provided lat,lng
  void getNearbyPlaces(LatLng latLng) {
    LocationUtils.getAppHeaders().then((headers) {
      var endpoint = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?" +
          "key=${widget.apiKey}&" +
          "location=${latLng.latitude},${latLng.longitude}&radius=150" +
          "&language=${widget.language}";

      return http.get(Uri.parse(endpoint), headers: headers);
    }).then((response) {
      if (response.statusCode == 200) {
        nearbyPlaces.clear();
        for (Map<String, dynamic> item in jsonDecode(response.body)['results']) {
          var nearbyPlace = NearbyPlace();

          nearbyPlace.name = item['name'];
          nearbyPlace.icon = item['icon'];
          double latitude = item['geometry']['location']['lat'];
          double longitude = item['geometry']['location']['lng'];

          var _latLng = LatLng(latitude, longitude);

          nearbyPlace.latLng = _latLng;

          nearbyPlaces.add(nearbyPlace);
        }
      }

      // to update the nearby places
      setState(() {
        // this is to require the result to show
        hasSearchTerm = false;
      });
    }).catchError((dynamic error) {});
  }

  /// This method gets the human readable name of the location. Mostly appears
  /// to be the road name and the locality.
  Future reverseGeocodeLatLng(LatLng latLng) async {
    final endpoint =
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}" +
            "&key=${widget.apiKey}" +
            "&language=${widget.language}";

    final response =
        await http.get(Uri.parse(endpoint), headers: await LocationUtils.getAppHeaders());

    if (response.statusCode == 200) {
      Map<String, dynamic> responseJson = jsonDecode(response.body);

      String road;

      String placeId = responseJson['results'][0]['place_id'];

      if (responseJson['status'] == 'REQUEST_DENIED') {
        road = 'REQUEST DENIED = please see log for more details';
        print(responseJson['error_message']);
      } else {
        road = responseJson['results'][0]['address_components'][0]['short_name'];
      }

//      String locality =
//          responseJson['results'][0]['address_components'][1]['short_name'];

      setState(() {
        locationResult = LocationResult();
        locationResult?.address = road;
        locationResult?.latLng = latLng;
        locationResult?.placeId = placeId;
      });
    }
  }

  /// Moves the camera to the provided location and updates other UI features to
  /// match the location.
  void moveToLocation(LatLng latLng) {
    mapKey.currentState?.mapController.future.then((controller) {
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 16,
          ),
        ),
      );
    });

    reverseGeocodeLatLng(latLng);

    getNearbyPlaces(latLng);
  }

  @override
  void dispose() {
    clearOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: Builder(builder: (context) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            elevation: 0,
            // backgroundColor: Colors.white,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).appBarTheme.backgroundColor
                : Colors.white,
            key: appBarKey,
            leading: IconButton(
              key: Key('journey_to_dashboard_nav'),
              icon: Icon(
                Icons.arrow_back,
                size: 25,
                color:
                    Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            title: Text(
              'Select location',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Colors.black,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: Size(MediaQuery.of(context).size.width, 50),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).appBarTheme.backgroundColor
                      : Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(39),
                    bottomRight: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      ///blur 12pt,
                      blurRadius: 12.0,

                      ///Offsets x=0,y=5,
                      offset: Offset(0, 3),

                      ///Shadow Color
                      color: Color(0xFF214A8119),
                    )
                  ],
                ),
                height: 60,
                child: Padding(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 10),
                  child: SearchInput(
                    (input) => searchPlace(input),
                    key: searchInputKey,
                    boxDecoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    hintText: widget.hintText,
                  ),
                ),
              ),
            ),
          ),
          body: MapPicker(
            widget.apiKey,
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            requiredGPS: widget.requiredGPS,
            myLocationButtonEnabled: widget.myLocationButtonEnabled,
            layersButtonEnabled: widget.layersButtonEnabled,
            automaticallyAnimateToCurrentLocation: widget.automaticallyAnimateToCurrentLocation,
            mapStylePath: widget.mapStylePath,
            appBarColor: widget.appBarColor,
            searchBarBoxDecoration: widget.searchBarBoxDecoration,
            hintText: widget.hintText,
            resultCardConfirmIcon: widget.resultCardConfirmIcon,
            resultCardAlignment: widget.resultCardAlignment,
            resultCardDecoration: widget.resultCardDecoration,
            resultCardPadding: widget.resultCardPadding,
            key: mapKey,
            language: widget.language,
            desiredAccuracy: widget.desiredAccuracy,
            geofenceRadius: widget.geofenceRadius,
            locationPickerType: widget.locationPickerType,
            existingLocationName: widget.existingLocationName,
          ),
        );
      }),
    );
  }
}

/// Returns a [LatLng] object of the location that was picked.
///
/// The [apiKey] argument API key generated from Google Cloud Console.
/// You can get an API key [here](https://cloud.google.com/maps-platform/)
///
/// [initialCenter] The geographical location that the camera is pointing
/// until the current user location is know if you want to change this
/// set [automaticallyAnimateToCurrentLocation] to false.
///
///
Future<dynamic> showLocationPicker(
  BuildContext context,
  String apiKey, {
  LatLng initialCenter = const LatLng(45.521563, -122.677433),
  double initialZoom = 16,
  bool requiredGPS = false,
  List<String>? countries,
  bool myLocationButtonEnabled = false,
  bool layersButtonEnabled = false,
  bool automaticallyAnimateToCurrentLocation = true,
  String? mapStylePath,
  Color appBarColor = Colors.transparent,
  LocationAccuracy desiredAccuracy = LocationAccuracy.best,
  BoxDecoration? searchBarBoxDecoration,
  String? hintText,
  Widget? resultCardConfirmIcon,
  Alignment? resultCardAlignment,
  EdgeInsets? resultCardPadding,
  Decoration? resultCardDecoration,
  String? language,
  dynamic locationPickerType,
  dynamic existingLocationName,
  dynamic geofenceRadius,
}) async {
  dynamic results = await Navigator.of(context).push<dynamic>(
    MaterialPageRoute<dynamic>(
      builder: (BuildContext context) {
        return LocationPicker(
          apiKey,
          initialCenter: initialCenter,
          initialZoom: initialZoom,
          requiredGPS: requiredGPS,
          myLocationButtonEnabled: myLocationButtonEnabled,
          layersButtonEnabled: layersButtonEnabled,
          automaticallyAnimateToCurrentLocation: automaticallyAnimateToCurrentLocation,
          mapStylePath: mapStylePath,
          appBarColor: appBarColor,
          hintText: hintText,
          searchBarBoxDecoration: searchBarBoxDecoration,
          resultCardConfirmIcon: resultCardConfirmIcon,
          resultCardAlignment: resultCardAlignment,
          resultCardPadding: resultCardPadding,
          resultCardDecoration: resultCardDecoration,
          countries: countries,
          language: language,
          desiredAccuracy: desiredAccuracy,
          locationPickerType: locationPickerType,
          geofenceRadius: geofenceRadius,
          existingLocationName: existingLocationName,
        );
      },
    ),
  );

  if (results != null && results.containsKey('location')) {
    return results['location'];
  } else {
    return null;
  }
}
