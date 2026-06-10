import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/weight_repository.dart';

class UserProvider extends ChangeNotifier {
  final WeightRepository _weightRepository = WeightRepository();
  
  UserProfile? _userProfile;
  bool _isLoading = false;
  
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  
  String get weightUnit => _userProfile?.weightUnit ?? 'kg';
  double? get currentWeight => _userProfile?.currentWeight;
  String get userName => _userProfile?.name ?? 'User';

  Future<void> loadUserProfile() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _userProfile = await _weightRepository.getUserProfile();
      
      // If no user profile exists, create a default one
      if (_userProfile == null) {
        _userProfile = UserProfile(
          name: 'User',
          createdDate: DateTime.now(),
          weightUnit: 'kg',
        );
        
        final id = await _weightRepository.insertUserProfile(_userProfile!);
        _userProfile = _userProfile!.copyWith(id: id);
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUserName(String name) async {
    if (_userProfile == null) return;
    
    try {
      final updatedProfile = _userProfile!.copyWith(name: name);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating user name: $e');
    }
  }

  Future<void> updateWeightUnit(String unit) async {
    if (_userProfile == null) return;
    
    try {
      // Update user profile
      final updatedProfile = _userProfile!.copyWith(weightUnit: unit);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating weight unit: $e');
    }
  }

  Future<void> updateCurrentWeight(double weight) async {
    if (_userProfile == null) return;
    
    try {
      final updatedProfile = _userProfile!.copyWith(currentWeight: weight);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating current weight: $e');
    }
  }

  Future<void> clearCurrentWeight() async {
    if (_userProfile == null) return;

    try {
      final updatedProfile = _userProfile!.copyWith(currentWeight: null);
      await _weightRepository.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing current weight: $e');
    }
  }

  // Helper method to convert weight between units
  double convertWeight(double weight, String fromUnit, String toUnit) {
    if (fromUnit == toUnit) return weight;
    
    if (fromUnit == 'kg' && toUnit == 'lbs') {
      return weight * 2.20462;
    } else if (fromUnit == 'lbs' && toUnit == 'kg') {
      return weight / 2.20462;
    }
    
    return weight;
  }

  // Format weight with appropriate unit
  String formatWeight(double weight, {String? unit}) {
    final displayUnit = unit ?? weightUnit;
    return '${weight.toStringAsFixed(1)} $displayUnit';
  }

  // Get weight in user's preferred unit
  double getWeightInPreferredUnit(double weight, String currentUnit) {
    return convertWeight(weight, currentUnit, weightUnit);
  }

  Future<void> initialize() async {
    await loadUserProfile();
  }
}