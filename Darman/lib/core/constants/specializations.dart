import 'package:flutter/material.dart';

class DoctorSpecialization {
  final String name;
  final IconData icon;

  const DoctorSpecialization({
    required this.name,
    required this.icon,
  });
}
const List<DoctorSpecialization> kDoctorSpecializations = [
  DoctorSpecialization(
    name: 'General Physician',
    icon: Icons.health_and_safety_rounded,
  ),
  DoctorSpecialization(
    name: 'Family Medicine',
    icon: Icons.family_restroom_rounded,
  ),
  DoctorSpecialization(
    name: 'Internal Medicine',
    icon: Icons.medical_services_rounded,
  ),
  DoctorSpecialization(
    name: 'Cardiologist',
    icon: Icons.favorite_rounded,
  ),
  DoctorSpecialization(
    name: 'Dermatologist',
    icon: Icons.face_retouching_natural_rounded,
  ),
  DoctorSpecialization(
    name: 'Endocrinologist',
    icon: Icons.bloodtype_rounded,
  ),
  DoctorSpecialization(
    name: 'Gastroenterologist',
    icon: Icons.local_dining_rounded,
  ),
  DoctorSpecialization(
    name: 'Gynecologist',
    icon: Icons.pregnant_woman_rounded,
  ),
  DoctorSpecialization(
    name: 'Obstetrician',
    icon: Icons.pregnant_woman_rounded,
  ),
  DoctorSpecialization(
    name: 'Pediatrician',
    icon: Icons.child_care_rounded,
  ),
  DoctorSpecialization(
    name: 'Neurologist',
    icon: Icons.psychology_rounded,
  ),
  DoctorSpecialization(
    name: 'Neurosurgeon',
    icon: Icons.psychology_rounded,
  ),
  DoctorSpecialization(
    name: 'Oncologist',
    icon: Icons.biotech_rounded,
  ),
  DoctorSpecialization(
    name: 'Ophthalmologist',
    icon: Icons.visibility_rounded,
  ),
  DoctorSpecialization(
    name: 'Orthopedic Surgeon',
    icon: Icons.accessibility_new_rounded,
  ),
  DoctorSpecialization(
    name: 'Pulmonologist',
    icon: Icons.air_rounded,
  ),
  DoctorSpecialization(
    name: 'Radiologist',
    icon: Icons.image_search_rounded,
  ),
  DoctorSpecialization(
    name: 'Urologist',
    icon: Icons.water_drop_rounded,
  ),
  DoctorSpecialization(
    name: 'Nephrologist',
    icon: Icons.water_drop_rounded,
  ),
  DoctorSpecialization(
    name: 'ENT Specialist',
    icon: Icons.hearing_rounded,
  ),
  DoctorSpecialization(
    name: 'General Surgeon',
    icon: Icons.medical_services_rounded,
  ),
  DoctorSpecialization(
    name: 'Plastic Surgeon',
    icon: Icons.face_rounded,
  ),
  DoctorSpecialization(
    name: 'Vascular Surgeon',
    icon: Icons.bloodtype_rounded,
  ),
  DoctorSpecialization(
    name: 'Cardiothoracic Surgeon',
    icon: Icons.favorite_border_rounded,
  ),
  DoctorSpecialization(
    name: 'Pediatric Surgeon',
    icon: Icons.child_care_rounded,
  ),
  DoctorSpecialization(
    name: 'Rheumatologist',
    icon: Icons.accessibility_new_rounded,
  ),
  DoctorSpecialization(
    name: 'Hematologist',
    icon: Icons.bloodtype_rounded,
  ),
  DoctorSpecialization(
    name: 'Infectious Disease Specialist',
    icon: Icons.coronavirus_rounded,
  ),
  DoctorSpecialization(
    name: 'Allergist & Immunologist',
    icon:  Icons.health_and_safety_rounded,
  ),
  DoctorSpecialization(
    name: 'Critical Care Specialist',
    icon: Icons.monitor_heart_rounded,
  ),
  DoctorSpecialization(
    name: 'Emergency Medicine Specialist',
    icon: Icons.emergency_rounded,
  ),
  DoctorSpecialization(
    name: 'Anesthesiologist',
    icon: Icons.medical_services_rounded,
  ),
  DoctorSpecialization(
    name: 'Pathologist',
    icon: Icons.biotech_rounded,
  ),
  DoctorSpecialization(
    name: 'Psychiatrist',
    icon: Icons.self_improvement_rounded,
  ),
  DoctorSpecialization(
    name: 'Psychologist',
    icon: Icons.psychology_alt_rounded,
  ),
  DoctorSpecialization(
    name: 'Dentist',
    icon: Icons.medical_information_rounded,
  ),
  DoctorSpecialization(
    name: 'Orthodontist',
    icon: Icons.sentiment_satisfied_alt_rounded,
  ),
  DoctorSpecialization(
    name: 'Prosthodontist',
    icon: Icons.medical_information_rounded,
  ),
  DoctorSpecialization(
    name: 'Periodontist',
    icon: Icons.medical_information_rounded,
  ),
  DoctorSpecialization(
    name: 'Endodontist',
    icon: Icons.medical_information_rounded,
  ),
  DoctorSpecialization(
    name: 'Oral & Maxillofacial Surgeon',
    icon: Icons.face_rounded,
  ),
  DoctorSpecialization(
    name: 'Physiotherapist',
    icon: Icons.directions_run_rounded,
  ),
  DoctorSpecialization(
    name: 'Occupational Therapist',
    icon: Icons.accessibility_new_rounded,
  ),
  DoctorSpecialization(
    name: 'Speech Therapist',
    icon: Icons.record_voice_over_rounded,
  ),
  DoctorSpecialization(
    name: 'Nutritionist',
    icon: Icons.restaurant_rounded,
  ),
  DoctorSpecialization(
    name: 'Dietitian',
    icon: Icons.restaurant_menu_rounded,
  ),
  DoctorSpecialization(
    name: 'Pain Management Specialist',
    icon: Icons.healing_rounded,
  ),
  DoctorSpecialization(
    name: 'Sleep Medicine Specialist',
    icon: Icons.bedtime_rounded,
  ),
  DoctorSpecialization(
    name: 'Geriatrician',
    icon: Icons.elderly_rounded,
  ),
  DoctorSpecialization(
    name: 'Palliative Care Specialist',
    icon: Icons.volunteer_activism_rounded,
  ),
  DoctorSpecialization(
    name: 'Sports Medicine Specialist',
    icon: Icons.sports_rounded,
  ),
  DoctorSpecialization(
    name: 'Rehabilitation Medicine Specialist',
    icon: Icons.accessibility_new_rounded,
  ),
  DoctorSpecialization(
    name: 'Geneticist',
    icon: Icons.science_rounded,
  ),
  DoctorSpecialization(
    name: 'Nuclear Medicine Specialist',
    icon:  Icons.science_rounded,
  ),
  DoctorSpecialization(
    name: 'Clinical Pharmacologist',
    icon: Icons.medication_rounded,
  ),
];


DoctorSpecialization? findSpecialization(String? name) {
  if (name == null || name.trim().isEmpty) {
    return null;
  }

  for (final specialization in kDoctorSpecializations) {
    if (specialization.name.toLowerCase() == name.trim().toLowerCase()) {
      return specialization;
    }
  }

  return null;
}

IconData specializationIcon(String specialization) {
  return findSpecialization(specialization)?.icon ??
      Icons.medical_services_rounded;
}