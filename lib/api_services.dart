import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:io';

import 'package:resume_analyzer_app/screens/upload_screens.dart';

class ApiService {
  static const String _baseUrl = "https://resumemate.onrender.com/api";
  static const _adzunaAppId = '2df6159c';
  static const _adzunaAppKey = '2f5585c04b53db6ec3ac16807db8ceca';
  static const _indeedPublisherId = 'YOUR_INDEED_PUBLISHER_ID';
  static const _linkedInClientId =
      'YOUR_LINKEDIN_CLIENT_ID'; // if u have then Add
  static const _linkedInClientSecret =
      'YOUR_LINKEDIN_CLIENT_SECRET'; // if u have then Add

  static Future<Map<String, dynamic>> uploadResume(File file) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/resumes/upload/'),
      );

      // Add file with proper content type
      final fileExt = file.path.split('.').last.toLowerCase();
      final contentType = fileExt == 'pdf'
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(contentType),
      ));

      final response = await http.Response.fromStream(await request.send());
      final responseData = json.decode(response.body);

      if (response.statusCode >= 400) {
        throw DatabaseException(responseData['error'] ?? 'Upload failed');
      }

      return responseData;
    } catch (e) {
      throw DatabaseException('Upload error: ${e.toString()}');
    }
  }

  static Future<Map<String, dynamic>> analyzeResume(int resumeId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/resumes/$resumeId/analyze/'),
      headers: {'Accept': 'application/json'},
    );

    final responseData = json.decode(response.body);

    if (response.statusCode == 200) {
      if (responseData['status'] == 'success') {
        return responseData['data']; // Return the nested data object
      } else {
        throw DatabaseException(responseData['message'] ?? 'Analysis failed');
      }
    } else if (response.statusCode == 201) {
      // Handle 201 Created if your API returns it
      return responseData;
    } else {
      throw DatabaseException(responseData['message'] ??
          'Analysis failed with status ${response.statusCode}');
    }
  }

  static Future<List<dynamic>> getJobsFromAllPortals({
    required List<String> skills,
    String country = 'us',
    int results = 5,
    required String experienceLevel,
    required List<String> categories,
  }) async {
    try {
      String skillsQuery = skills.join(',');

      final results = await Future.wait([
        _getAdzunaJobs(
          skills: skillsQuery,
          country: country,
        ),
        _getIndeedJobs(
          skills: skillsQuery,
          country: country,
        ),
        _getLinkedInJobs(
          skills: skillsQuery,
          country: country,
        ),
      ]);

      final allJobs = results.expand((jobs) => jobs).toList();
      if (allJobs.isEmpty) {
        print('❌ No jobs found across all portals.');
      } else {
        print('✅ Combined Jobs List: $allJobs');
      }
      return _processJobResults(allJobs);
    } catch (e) {
      print('❌ Error fetching jobs: ${e.toString()}');
      throw Exception('Failed to load jobs: ${e.toString()}');
    }
  }

  static Future<List<dynamic>> _getAdzunaJobs({
    required String skills,
    String country = 'gb',
    int results = 5,
  }) async {
    try {
      final adzunaUrl = 'https://api.adzuna.com/v1/api/jobs/$country/search/1?'
          'app_id=$_adzunaAppId&'
          'app_key=$_adzunaAppKey&'
          'results_per_page=$results&'
          'what=$skills'; // Now using the skills query

      print('🌍 Adzuna Request URL: $adzunaUrl'); // Debugging URL
      final response = await http.get(Uri.parse(adzunaUrl));

      if (response.statusCode == 200) {
        print('✅ Adzuna Response: ${response.body}');
        return (jsonDecode(response.body)['results'] as List)
            .map((job) => _formatAdzunaJob(job))
            .toList();
      } else {
        print('❌ Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Failed to fetch jobs from Adzuna: ${e.toString()}');
      return [];
    }
  }

  static Future<List<dynamic>> _getIndeedJobs({
    required String skills,
    String country = 'gb',
    int results = 5,
  }) async {
    try {
      final indeedUrl = 'https://api.indeed.com/ads/apisearch?'
          'publisher=$_indeedPublisherId&'
          'q=$skills&'
          'l=&co=$country&'
          'limit=$results&'
          'format=json&'
          'v=2';

      print('🌍 Indeed Request URL: $indeedUrl'); // Debugging URL
      final response = await http.get(Uri.parse(indeedUrl));

      if (response.statusCode == 200) {
        print('✅ Indeed Response: ${response.body}');
        return (jsonDecode(response.body)['results'] as List)
            .map((job) => _formatIndeedJob(job))
            .toList();
      } else {
        print('❌ Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Failed to fetch jobs from Indeed: ${e.toString()}');
      return [];
    }
  }

  static Future<List<dynamic>> _getLinkedInJobs({
    required String skills,
    String country = 'gb',
    int results = 5,
  }) async {
    try {
      final linkedInUrl = 'https://api.linkedin.com/v2/jobSearch?'
          'keywords=$skills&'
          'location=country:$country&'
          'count=$results';

      print('🌍 LinkedIn Request URL: $linkedInUrl'); // Debugging URL
      final response = await http.get(
        Uri.parse(linkedInUrl),
        headers: {
          'Authorization': 'Bearer YOUR_ACCESS_TOKEN',
          'X-Restli-Protocol-Version': '2.0.0',
        },
      );

      if (response.statusCode == 200) {
        print('✅ LinkedIn Response: ${response.body}');
        return (jsonDecode(response.body)['elements'] as List)
            .map((job) => _formatLinkedInJob(job))
            .toList();
      } else {
        print('❌ Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Failed to fetch jobs from LinkedIn: ${e.toString()}');
      return [];
    }
  }

  // Job formatting helpers
  static Map<String, dynamic> _formatAdzunaJob(Map<String, dynamic> job) {
    return {
      'title': job['title'],
      'company': {'display_name': job['company']['display_name']},
      'location': {'display_name': job['location']['display_name']},
      'created': job['created'],
      'redirect_url': job['redirect_url'],
      'description': job['description'],
      'salary_min': job['salary_min'],
      'salary_max': job['salary_max'],
      'source': 'Adzuna',
    };
  }

  static Map<String, dynamic> _formatIndeedJob(Map<String, dynamic> job) {
    return {
      'title': job['jobtitle'],
      'company': {'display_name': job['company']},
      'location': {'display_name': job['formattedLocation']},
      'created': job['date'],
      'redirect_url': job['url'],
      'description': job['snippet'],
      'salary': job['salary'],
      'source': 'Indeed',
    };
  }

  static Map<String, dynamic> _formatLinkedInJob(Map<String, dynamic> job) {
    return {
      'title': job['title']['text'],
      'company': {'display_name': job['companyName']},
      'location': {'display_name': job['formattedLocation']},
      'created': job['listedAt'],
      'redirect_url': job['jobUrl'],
      'description': job['description']['text'],
      'source': 'LinkedIn',
    };
  }

  // Process and sort combined results
  static List<dynamic> _processJobResults(List<dynamic> jobs) {
    final seenJobIds = <String>{};
    final uniqueJobs = <Map<String, dynamic>>[];

    for (var job in jobs) {
      if (!seenJobIds.contains(job['redirect_url'])) {
        seenJobIds.add(job['redirect_url']);
        uniqueJobs.add(job);
      }
    }

    uniqueJobs.sort((a, b) {
      final createdAtA = DateTime.parse(a['created']);
      final createdAtB = DateTime.parse(b['created']);
      return createdAtB.compareTo(createdAtA);
    });

    return uniqueJobs;
  }
}
