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
  // ─────────────────────────────────────────────
  // GENERAL & INTERNAL MEDICINE
  // ─────────────────────────────────────────────
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
    name: 'Geriatrician',
    icon: Icons.elderly_rounded,
  ),
  DoctorSpecialization(
    name: 'Emergency Medicine Specialist',
    icon: Icons.emergency_rounded,
  ),
  DoctorSpecialization(
    name: 'Critical Care Specialist',
    icon: Icons.monitor_heart_rounded,
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
    name: 'Palliative Care Specialist',
    icon: Icons.volunteer_activism_rounded,
  ),
  DoctorSpecialization(
    name: 'Rehabilitation Medicine Specialist',
    icon: Icons.accessibility_new_rounded,
  ),

  // ─────────────────────────────────────────────
  // CARDIOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Cardiologist',
    icon: Icons.favorite_rounded,
  ),
  DoctorSpecialization(
    name: 'Interventional Cardiologist',
    icon: Icons.favorite_rounded,
  ),
  DoctorSpecialization(
    name: 'Pediatric Cardiologist',
    icon: Icons.favorite_border_rounded,
  ),
  DoctorSpecialization(
    name: 'Cardiovascular Surgeon',
    icon: Icons.favorite_rounded,
  ),
  DoctorSpecialization(
    name: 'Cardiothoracic Surgeon',
    icon: Icons.favorite_border_rounded,
  ),

  // ─────────────────────────────────────────────
  // ENDOCRINOLOGY & METABOLIC
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Endocrinologist',
    icon: Icons.bloodtype_rounded,
  ),
  DoctorSpecialization(
    name: 'Diabetologist',
    icon: Icons.bloodtype_rounded,
  ),

  // ─────────────────────────────────────────────
  // GASTROENTEROLOGY & LIVER
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Gastroenterologist',
    icon: Icons.local_dining_rounded,
  ),
  DoctorSpecialization(
    name: 'Hepatologist',
    icon: Icons.local_dining_rounded,
  ),

  // ─────────────────────────────────────────────
  // KIDNEY & URINARY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Nephrologist',
    icon: Icons.water_drop_rounded,
  ),
  DoctorSpecialization(
    name: 'Urologist',
    icon: Icons.water_drop_rounded,
  ),

  // ─────────────────────────────────────────────
  // NEUROLOGY & NEUROSURGERY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Neurologist',
    icon: Icons.psychology_rounded,
  ),
  DoctorSpecialization(
    name: 'Pediatric Neurologist',
    icon: Icons.psychology_rounded,
  ),
  DoctorSpecialization(
    name: 'Neurosurgeon',
    icon: Icons.psychology_rounded,
  ),

  // ─────────────────────────────────────────────
  // DERMATOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Dermatologist',
    icon: Icons.face_retouching_natural_rounded,
  ),
  DoctorSpecialization(
    name: 'Dermatopathologist',
    icon: Icons.biotech_rounded,
  ),

  // ─────────────────────────────────────────────
  // PEDIATRICS
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Pediatrician',
    icon: Icons.child_care_rounded,
  ),
  DoctorSpecialization(
    name: 'Pediatric Surgeon',
    icon: Icons.child_care_rounded,
  ),

  // ─────────────────────────────────────────────
  // WOMEN'S HEALTH
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Gynecologist',
    icon: Icons.pregnant_woman_rounded,
  ),
  DoctorSpecialization(
    name: 'Obstetrician',
    icon: Icons.pregnant_woman_rounded,
  ),
  DoctorSpecialization(
    name: 'Obstetrician & Gynecologist',
    icon: Icons.pregnant_woman_rounded,
  ),

  // ─────────────────────────────────────────────
  // ONCOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Oncologist',
    icon: Icons.biotech_rounded,
  ),
  DoctorSpecialization(
    name: 'Surgical Oncologist',
    icon: Icons.medical_services_rounded,
  ),

  // ─────────────────────────────────────────────
  // EYE CARE
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Ophthalmologist',
    icon: Icons.visibility_rounded,
  ),
  DoctorSpecialization(
    name: 'Ophthalmic Surgeon',
    icon: Icons.visibility_rounded,
  ),

  // ─────────────────────────────────────────────
  // ENT
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'ENT Specialist',
    icon: Icons.hearing_rounded,
  ),
  DoctorSpecialization(
    name: 'Otolaryngologist',
    icon: Icons.hearing_rounded,
  ),

  // ─────────────────────────────────────────────
  // ORTHOPEDICS
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Orthopedic Surgeon',
    icon: Icons.accessibility_new_rounded,
  ),

  // ─────────────────────────────────────────────
  // GENERAL & SPECIALIZED SURGERY
  // ─────────────────────────────────────────────
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
    name: 'Breast Surgeon',
    icon: Icons.medical_services_rounded,
  ),
  DoctorSpecialization(
    name: 'Colorectal Surgeon',
    icon: Icons.medical_services_rounded,
  ),
  DoctorSpecialization(
    name: 'Gastrointestinal Surgeon',
    icon: Icons.medical_services_rounded,
  ),
  DoctorSpecialization(
    name: 'Pediatric Surgeon',
    icon: Icons.child_care_rounded,
  ),
  DoctorSpecialization(
    name: 'Oral & Maxillofacial Surgeon',
    icon: Icons.face_rounded,
  ),

  // ─────────────────────────────────────────────
  // PULMONOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Pulmonologist',
    icon: Icons.air_rounded,
  ),

  // ─────────────────────────────────────────────
  // RADIOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Radiologist',
    icon: Icons.image_search_rounded,
  ),
  DoctorSpecialization(
    name: 'Interventional Radiologist',
    icon: Icons.image_search_rounded,
  ),
  DoctorSpecialization(
    name: 'Nuclear Radiologist',
    icon: Icons.image_search_rounded,
  ),
  DoctorSpecialization(
    name: 'Nuclear Medicine Specialist',
    icon: Icons.science_rounded,
  ),

  // ─────────────────────────────────────────────
  // RHEUMATOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Rheumatologist',
    icon: Icons.accessibility_new_rounded,
  ),

  // ─────────────────────────────────────────────
  // BLOOD & IMMUNOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Hematologist',
    icon: Icons.bloodtype_rounded,
  ),
  DoctorSpecialization(
    name: 'Clinical Hematologist',
    icon: Icons.bloodtype_rounded,
  ),
  DoctorSpecialization(
    name: 'Allergist & Immunologist',
    icon: Icons.health_and_safety_rounded,
  ),
  DoctorSpecialization(
    name: 'Clinical Immunologist',
    icon: Icons.health_and_safety_rounded,
  ),

  // ─────────────────────────────────────────────
  // INFECTIOUS DISEASE
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Infectious Disease Specialist',
    icon: Icons.coronavirus_rounded,
  ),

  // ─────────────────────────────────────────────
  // ANESTHESIA
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Anesthesiologist',
    icon: Icons.medical_services_rounded,
  ),

  // ─────────────────────────────────────────────
  // PATHOLOGY & LABORATORY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Pathologist',
    icon: Icons.biotech_rounded,
  ),

  // ─────────────────────────────────────────────
  // MENTAL HEALTH
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Psychiatrist',
    icon: Icons.self_improvement_rounded,
  ),
  DoctorSpecialization(
    name: 'Psychologist',
    icon: Icons.psychology_alt_rounded,
  ),

  // ─────────────────────────────────────────────
  // DENTISTRY
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // ALLIED HEALTH
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // SPORTS & REHABILITATION
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Sports Medicine Specialist',
    icon: Icons.sports_rounded,
  ),

  // ─────────────────────────────────────────────
  // GENETICS & PHARMACOLOGY
  // ─────────────────────────────────────────────
  DoctorSpecialization(
    name: 'Geneticist',
    icon: Icons.science_rounded,
  ),
  DoctorSpecialization(
    name: 'Clinical Pharmacologist',
    icon: Icons.medication_rounded,
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

  final normalizedName = name.trim().toLowerCase();

  for (final specialization in kDoctorSpecializations) {
    if (specialization.name.toLowerCase() == normalizedName) {
      return specialization;
    }
  }

  return null;
}

IconData specializationIcon(String specialization) {
  return findSpecialization(specialization)?.icon ??
      Icons.medical_services_rounded;
}