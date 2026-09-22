/// Mapping canonique entre les pages de l'espace scolaire et les modules
/// activables d'un établissement.
const Map<String, String> schoolPageModules = {
  'academic_years': 'academic_years',
  'classes': 'classes',
  'students': 'students',
  'teachers': 'teachers',
  'subjects': 'subjects',
  'affectations': 'affectations',
  'grades': 'grades',
  'tracking': 'grades',
  // Un devoir surveillé est une évaluation notée : il dépend du moteur grades.
  'assignments': 'grades',
  'attendance': 'attendance',
  'behavior': 'behavior',
  'schedule': 'schedule',
  'finance': 'finance',
  'documents': 'documents',
  'statistics': 'statistics',
};

bool isSchoolPageEnabled(String pageId, Iterable<String> enabledModules) {
  final moduleId = schoolPageModules[pageId];
  return moduleId == null || enabledModules.contains(moduleId);
}
