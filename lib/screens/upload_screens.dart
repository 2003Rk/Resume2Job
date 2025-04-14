import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:resume_analyzer_app/api_services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({Key? key}) : super(key: key);

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _resumeFile;
  bool _isProcessing = false;
  String _statusMessage = '';
  Color _statusColor = Colors.blue;
  Map<String, dynamic>? _analysisResult;
  List<dynamic> _jobRecommendations = [];
  bool _loadingJobs = false;
  final Connectivity _connectivity = Connectivity();
  String _selectedCountry = 'in'; // Default to India

  // List of common countries with their codes and names
  final List<Map<String, String>> _countries = [
    {'code': 'in', 'name': 'India'},
    {'code': 'us', 'name': 'United States'},
    {'code': 'gb', 'name': 'United Kingdom'},
    {'code': 'ca', 'name': 'Canada'},
    {'code': 'au', 'name': 'Australia'},
    {'code': 'de', 'name': 'Germany'},
    {'code': 'fr', 'name': 'France'},
    {'code': 'sg', 'name': 'Singapore'},
    {'code': 'ae', 'name': 'UAE'},
    {'code': 'nz', 'name': 'New Zealand'},
  ];

  Future<bool> _checkInternetConnection() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  Future<void> _showNoInternetDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('No Internet Connection'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Please connect to the internet to use this feature.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _resumeFile = File(result.files.single.path!);
          _statusMessage = 'File selected: ${result.files.single.name}';
          _statusColor = Colors.blue;
          _analysisResult = null;
          _jobRecommendations = [];
        });
      }
    } catch (e) {
      _showError('Error selecting file. Please try again.');
    }
  }

  Future<void> _uploadAndAnalyze() async {
    if (_resumeFile == null) return;

    if (!await _checkInternetConnection()) {
      await _showNoInternetDialog();
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing your resume...';
      _statusColor = Colors.blue;
    });

    try {
      final uploadData = await ApiService.uploadResume(_resumeFile!)
          .timeout(const Duration(seconds: 30));

      setState(() => _statusMessage = 'Analyzing content...');

      final analysisData = await ApiService.analyzeResume(uploadData['id'])
          .timeout(const Duration(seconds: 30));

      setState(() {
        _analysisResult = {
          'ats_score': analysisData['ats_score'],
          'score_breakdown': analysisData['score_breakdown'],
          'skills': analysisData['skills'],
          'experience': analysisData['experience'],
          'education': analysisData['education'],
          'metadata': analysisData['metadata'],
        };
        _statusMessage = 'Analysis complete!';
        _statusColor = Colors.green;
      });

      await _fetchJobRecommendations();
    } on TimeoutException {
      _showError('Request timed out. Please try again.');
    } on SocketException {
      _showError('Connection lost. Please check your internet.');
    } catch (e) {
      _showError('An error occurred during analysis.');
      debugPrint('Analysis error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _statusMessage = message;
      _statusColor = Colors.red;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _fetchJobRecommendations() async {
    if (_analysisResult == null || _analysisResult!['skills'] == null) return;

    if (!await _checkInternetConnection()) {
      await _showNoInternetDialog();
      return;
    }

    setState(() => _loadingJobs = true);

    try {
      List<String> skills = List<String>.from(_analysisResult!['skills']);
      if (skills.length > 10) skills = skills.sublist(0, 10);

      List<dynamic> allJobs = [];

      // Attempt with all skills
      var jobs = await _searchJobsWithSkills(skills);
      allJobs.addAll(jobs);

      // Fallback to fewer skills if no results
      if (allJobs.isEmpty && skills.length > 3) {
        jobs = await _searchJobsWithSkills(skills.sublist(0, 3));
        allJobs.addAll(jobs);
      }

      // Fallback to individual skills if still no results
      if (allJobs.isEmpty) {
        for (String skill in skills) {
          jobs = await _searchJobsWithSkills([skill]);
          allJobs.addAll(jobs);
          if (allJobs.length > 10) break;
        }
      }

      final uniqueJobs = _removeDuplicateJobs(allJobs);

      setState(() {
        _jobRecommendations = uniqueJobs;
        if (uniqueJobs.isEmpty) {
          _statusMessage = 'Analysis complete! Try broadening your skills.';
        }
      });
    } on TimeoutException {
      _showError('Job search timed out. Please try again.');
    } catch (e) {
      _showError('Failed to load job recommendations.');
      debugPrint('Job search error: $e');
    } finally {
      if (mounted) setState(() => _loadingJobs = false);
    }
  }

  Future<List<dynamic>> _searchJobsWithSkills(List<String> skills) async {
    try {
      return await ApiService.getJobsFromAllPortals(
        skills: skills,
        country: _selectedCountry,
        results: 20,
        experienceLevel: _getExperienceLevel(),
        categories: [],
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Job search error: $e');
      return [];
    }
  }

  Future<void> _fetchBroaderJobRecommendations() async {
    if (!await _checkInternetConnection()) {
      await _showNoInternetDialog();
      return;
    }

    setState(() => _loadingJobs = true);

    try {
      final broaderCategories = _getBroaderCategories();
      final jobs = await ApiService.getJobsFromAllPortals(
        categories: broaderCategories,
        country: _selectedCountry,
        results: 50,
        skills: [],
        experienceLevel: '',
      ).timeout(const Duration(seconds: 30));

      setState(() => _jobRecommendations = jobs);
    } on TimeoutException {
      _showError('Request timed out. Please try again.');
    } catch (e) {
      _showError('Failed to load broader job categories.');
      debugPrint('Broader jobs error: $e');
    } finally {
      if (mounted) setState(() => _loadingJobs = false);
    }
  }

  List<String> _getBroaderCategories() {
    const categoryMap = {
      'Flutter': 'Mobile Development',
      'React': 'Frontend Development',
      'Node.js': 'Backend Development',
      'Python': 'Data Science',
      'Java': 'Enterprise Development',
      'SQL': 'Database Administration',
      'AWS': 'Cloud Computing',
    };

    final skills = _analysisResult?['skills']?.cast<String>() ?? [];
    final categories = <String>{};

    for (var skill in skills) {
      if (categoryMap.containsKey(skill)) {
        categories.add(categoryMap[skill]!);
      }
    }

    return categories.isNotEmpty
        ? categories.toList()
        : ['Information Technology', 'Software Development'];
  }

  List<dynamic> _removeDuplicateJobs(List<dynamic> jobs) {
    final seen = <String>{};
    return jobs.where((job) {
      final key = '${job['title']}-${job['company']?['display_name']}';
      return seen.add(key);
    }).toList();
  }

  String _getExperienceLevel() {
    final experience = _analysisResult?['experience'];
    final years = experience is String
        ? int.tryParse(experience) ?? 0
        : experience is int
            ? experience
            : 0;

    if (years >= 10) return 'senior';
    if (years >= 5) return 'mid-level';
    return 'entry-level';
  }

  Color _getScoreColor(double score) {
    if (score >= 75) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _getScoreFeedback(double score) {
    if (score >= 75) return 'Excellent! Your resume is well optimized.';
    if (score >= 50) return 'Good, but could be improved further.';
    return 'Needs significant improvement to pass ATS screening.';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Resume Analyzer',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 22,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.grey[800]),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUploadSection(isSmallScreen),
            if (_statusMessage.isNotEmpty) _buildStatusIndicator(isSmallScreen),
            if (_analysisResult != null) ...[
              SizedBox(height: isSmallScreen ? 16 : 24),
              _buildScoreCard(isSmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 24),
              _buildScoreBreakdown(isSmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 24),
              _buildSection('SKILLS IDENTIFIED', _analysisResult!['skills'],
                  isSmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 24),
              _buildSection('EXPERIENCE',
                  {'Years': _analysisResult!['experience']}, isSmallScreen),
              if (_analysisResult!['education'] != null) ...[
                SizedBox(height: isSmallScreen ? 16 : 24),
                _buildSection(
                    'EDUCATION', _analysisResult!['education'], isSmallScreen),
              ],
              if (_analysisResult!['metadata'] != null) ...[
                SizedBox(height: isSmallScreen ? 16 : 24),
                _buildSection(
                    'WORK HISTORY',
                    {
                      'Positions':
                          _analysisResult!['metadata']['positions'] ?? [],
                      'Organizations':
                          _analysisResult!['metadata']['organizations'] ?? [],
                    },
                    isSmallScreen),
              ],
              SizedBox(height: isSmallScreen ? 16 : 24),
              _buildJobRecommendations(isSmallScreen),
              SizedBox(height: isSmallScreen ? 24 : 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection(bool isSmallScreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: Column(
          children: [
            // Country selection dropdown
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.3),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCountry,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.grey[800],
                  ),
                  items: _countries.map((country) {
                    return DropdownMenuItem<String>(
                      value: country['code'],
                      child: Text(country['name']!),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedCountry = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
            SizedBox(height: isSmallScreen ? 4 : 6),
            // Text showing selected country
            Text(
              'Searching jobs in ${_countries.firstWhere((c) => c['code'] == _selectedCountry)['name']}',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),

            // File upload section
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding:
                    EdgeInsets.symmetric(vertical: isSmallScreen ? 20 : 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: isSmallScreen ? 36 : 40,
                      color: Colors.blue[400],
                    ),
                    SizedBox(height: isSmallScreen ? 6 : 8),
                    Text(
                      _resumeFile == null
                          ? 'Upload Your Resume'
                          : 'Resume Selected',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    if (_resumeFile != null) ...[
                      SizedBox(height: isSmallScreen ? 2 : 4),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 8 : 16),
                        child: Text(
                          _resumeFile!.path.split('/').last,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_resumeFile != null) ...[
              SizedBox(height: isSmallScreen ? 16 : 20),
              SizedBox(
                width: double.infinity,
                height: isSmallScreen ? 48 : 50,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _uploadAndAnalyze,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'ANALYZE RESUME',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            fontSize: isSmallScreen ? 14 : 16,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.only(top: isSmallScreen ? 12 : 16),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        decoration: BoxDecoration(
          color: _statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _statusColor == Colors.red
                  ? Icons.error_outline
                  : _statusColor == Colors.green
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
              color: _statusColor,
              size: isSmallScreen ? 20 : 24,
            ),
            SizedBox(width: isSmallScreen ? 8 : 12),
            Expanded(
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: _statusColor,
                  fontSize: isSmallScreen ? 14 : 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard(bool isSmallScreen) {
    final score = _analysisResult?['ats_score']?.toDouble() ?? 0.0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getScoreColor(score).withOpacity(0.8),
            _getScoreColor(score).withOpacity(0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: Column(
          children: [
            Text(
              'ATS COMPATIBILITY',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Stack(
              alignment: Alignment.center,
              children: [
                CircularPercentIndicator(
                  radius: isSmallScreen ? 60 : 80,
                  lineWidth: isSmallScreen ? 10 : 12,
                  percent: score / 100,
                  center: const SizedBox(),
                  progressColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  circularStrokeCap: CircularStrokeCap.round,
                ),
                Column(
                  children: [
                    Text(
                      '${score.round()}%',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 28 : 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Score',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Text(
              _getScoreFeedback(score),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBreakdown(bool isSmallScreen) {
    final breakdown = _analysisResult?['score_breakdown'] ?? {};
    if (breakdown.isEmpty) return const SizedBox();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SCORE BREAKDOWN',
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            ...breakdown.entries.map((entry) {
              final percentage = entry.value / 100;
              return Padding(
                padding: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key
                              .toString()
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 11 : 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '${entry.value.round()} pts',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isSmallScreen ? 6 : 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage,
                        minHeight: isSmallScreen ? 6 : 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getScoreColor(percentage * 100),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, dynamic content, bool isSmallScreen) {
    if (content == null || (content is List && content.isEmpty)) {
      return const SizedBox();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: isSmallScreen ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            if (content is List)
              Wrap(
                spacing: isSmallScreen ? 6 : 8,
                runSpacing: isSmallScreen ? 6 : 8,
                children: content
                    .map((item) => Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 10 : 12,
                            vertical: isSmallScreen ? 6 : 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.toString(),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              color: Colors.blue[800],
                            ),
                          ),
                        ))
                    .toList(),
              )
            else if (content is Map)
              ...content.entries.map((entry) => Padding(
                    padding:
                        EdgeInsets.symmetric(vertical: isSmallScreen ? 4 : 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.key}: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                            fontSize: isSmallScreen ? 13 : 14,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value is List
                                ? entry.value.join(', ')
                                : entry.value.toString(),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ))
            else
              Text(
                content.toString(),
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: isSmallScreen ? 13 : 14,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobRecommendations(bool isSmallScreen) {
    if (_loadingJobs) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
        ),
      );
    }

    if (_jobRecommendations.isEmpty) {
      return Column(
        children: [
          SizedBox(height: isSmallScreen ? 12 : 20),
          Text(
            'No jobs found matching your exact skills',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: isSmallScreen ? 12 : 16),
          OutlinedButton(
            onPressed: _fetchBroaderJobRecommendations,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 16 : 24,
                vertical: isSmallScreen ? 10 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: Colors.blue[600]!),
            ),
            child: Text(
              'Show More General Job Categories',
              style: TextStyle(
                color: Colors.blue[600],
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
        ],
      );
    }

    final skills = _analysisResult?['skills'] is List
        ? List<String>.from(_analysisResult!['skills'])
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
          child: Text(
            'RECOMMENDED JOBS',
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 1.2,
            ),
          ),
        ),
        ..._jobRecommendations
            .map((job) => _buildJobCard(job, skills, isSmallScreen)),
      ],
    );
  }

  Widget _buildJobCard(
      Map<String, dynamic> job, List<String> userSkills, bool isSmallScreen) {
    final title = job['title']?.toString() ?? 'No title';
    final company = job['company'] is Map
        ? job['company']['display_name']?.toString() ?? ''
        : '';
    final location = job['location'] is Map
        ? job['location']['display_name']?.toString() ?? ''
        : '';
    final postedDate = job['created']?.toString().split('T')[0] ?? '';
    final url = job['redirect_url']?.toString();

    final matchedSkills = userSkills.where((skill) {
      final skillLower = skill.toLowerCase();
      final titleLower = title.toLowerCase();
      final descLower = job['description']?.toString().toLowerCase() ?? '';
      return titleLower.contains(skillLower) || descLower.contains(skillLower);
    }).toList();

    return Card(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (url != null && await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          }
        },
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: isSmallScreen ? 36 : 40,
                    height: isSmallScreen ? 36 : 40,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.work_outline,
                      color: Colors.blue[600],
                      size: isSmallScreen ? 18 : 20,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 15 : 16,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 2 : 4),
                        if (company.isNotEmpty)
                          Text(
                            company,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              if (location.isNotEmpty || postedDate.isNotEmpty)
                Row(
                  children: [
                    if (location.isNotEmpty) ...[
                      Icon(
                        Icons.location_on_outlined,
                        size: isSmallScreen ? 14 : 16,
                        color: Colors.grey[500],
                      ),
                      SizedBox(width: isSmallScreen ? 2 : 4),
                      Text(
                        location,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: isSmallScreen ? 12 : 13,
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 12 : 16),
                    ],
                    if (postedDate.isNotEmpty)
                      Text(
                        'Posted: $postedDate',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isSmallScreen ? 12 : 13,
                        ),
                      ),
                  ],
                ),
              if (matchedSkills.isNotEmpty) ...[
                SizedBox(height: isSmallScreen ? 8 : 12),
                Wrap(
                  spacing: isSmallScreen ? 6 : 8,
                  runSpacing: isSmallScreen ? 6 : 8,
                  children: matchedSkills
                      .map((skill) => Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 8 : 10,
                              vertical: isSmallScreen ? 4 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              skill,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 11 : 12,
                                color: Colors.green[800],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => message;
}
