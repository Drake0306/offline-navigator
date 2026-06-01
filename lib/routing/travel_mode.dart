/// Travel modes offered by the trip planner. [costing] is the Valhalla costing
/// model name used when building a route request.
enum TravelMode { car, motorbike, bike, walk }

extension TravelModeCosting on TravelMode {
  String get costing => switch (this) {
        TravelMode.car => 'auto',
        TravelMode.motorbike => 'motorcycle',
        TravelMode.bike => 'bicycle',
        TravelMode.walk => 'pedestrian',
      };

  String get label => switch (this) {
        TravelMode.car => 'Car',
        TravelMode.motorbike => 'Motorbike',
        TravelMode.bike => 'Bike',
        TravelMode.walk => 'Walk',
      };
}
