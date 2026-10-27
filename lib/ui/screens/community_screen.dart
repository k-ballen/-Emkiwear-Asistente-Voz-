import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';
import '../../models/user_profile.dart';
import '../widgets/assistant_button.dart';
import 'community_screen_data.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    this.initialTabIndex = 0,
    this.companionName,
    this.groupName,
    this.lessonTitle,
  });

  final int initialTabIndex;
  final String? companionName;
  final String? groupName;
  final String? lessonTitle;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _firebaseService = FirebaseService();
  bool _isPublic = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.index = widget.initialTabIndex;
    _loadPrivacy();
    _handlePendingNavigation();
  }

  /// After the first frame, if a companion name, group name or lesson title
  /// was passed (typically from a voice command), open the corresponding
  /// detail screen automatically.
  void _handlePendingNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.companionName != null) {
        _openCompanionByName(widget.companionName!);
      } else if (widget.groupName != null) {
        _openGroupByName(widget.groupName!);
      } else if (widget.lessonTitle != null) {
        _openLessonByName(widget.lessonTitle!);
      }
    });
  }

  /// Fetches all public companion profiles (demo + Firestore) and opens the
  /// detail sheet for the one whose name matches [name].
  void _openCompanionByName(String name) async {
    final allProfiles = demoCompanionProfiles.toList();
    try {
      final streamProfiles = await _firebaseService.getCommunityProfiles().first;
      allProfiles.addAll(streamProfiles);
    } catch (_) {
      // Firestore may be unavailable; fall back to demo profiles only.
    }
    final match = allProfiles.firstWhere(
      (p) => (p.name + ' ' + p.lastName).toLowerCase().contains(name.toLowerCase()),
      orElse: () => allProfiles.firstWhere(
        (p) => p.name.toLowerCase().contains(name.toLowerCase()),
        orElse: () => allProfiles.first,
      ),
    );
    showCompanionDetails(context, match);
  }

  /// Opens the detail page for the group whose title matches [name].
  void _openGroupByName(String name) {
    final group = demoGroups.firstWhere(
      (g) => g.title.toLowerCase().contains(name.toLowerCase()),
      orElse: () => demoGroups.first,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _GroupDetailScreen(group: group),
      ),
    );
  }

  /// Opens the detail page for the lesson whose title matches [name].
  void _openLessonByName(String name) {
    final lesson = demoLessons.firstWhere(
      (l) => l.title.toLowerCase().contains(name.toLowerCase()),
      orElse: () => demoLessons.first,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _LessonDetailScreen(title: lesson.title, content: lesson.content),
      ),
    );
  }

  void _loadPrivacy() async {
    final profile = await _firebaseService.getUserProfile();
    if (profile != null) {
      setState(() => _isPublic = profile.isPublic);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comunidad Parkinson', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purple.shade100,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF6A1B9A),
          labelColor: const Color(0xFF6A1B9A),
          tabs: const [
            Tab(text: 'Compañeros'),
            Tab(text: 'Grupos'),
            Tab(text: 'Lecciones'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple.shade50, Colors.white],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _CompanionsTab(firebaseService: _firebaseService),
            _GroupsTab(),
            _LessonsTab(),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const AssistantFloatingButton(),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'privacy_btn',
            onPressed: () {
              setState(() => _isPublic = !_isPublic);
              _firebaseService.updatePrivacy(_isPublic);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_isPublic ? 'Tu perfil ahora es público' : 'Tu perfil ahora es privado')),
              );
            },
            backgroundColor: _isPublic ? Colors.green : Colors.grey,
            icon: Icon(_isPublic ? Icons.visibility : Icons.visibility_off),
            label: Text(_isPublic ? 'Público' : 'Privado'),
          ),
        ],
      ),
    );
  }
}

class _CompanionsTab extends StatelessWidget {
  final FirebaseService firebaseService;
  const _CompanionsTab({required this.firebaseService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserProfile>>(
      stream: firebaseService.getCommunityProfiles(),
      builder: (context, snapshot) {
        final realProfiles = snapshot.data ?? [];
        final allProfiles = [...demoCompanionProfiles, ...realProfiles];

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: allProfiles.length,
          itemBuilder: (context, index) {
            final p = allProfiles[index];
            if (p.uid == firebaseService.currentUserId) return const SizedBox.shrink();
            
            final isDemo = p.uid.startsWith('demo');

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: const EdgeInsets.only(bottom: 15),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isDemo ? Colors.orange.shade200 : Colors.purple.shade200,
                        backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                        child: p.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                      title: Text('${p.name} ${isDemo ? "(DEMO)" : ""}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text('Diagnóstico: ${p.diagnosisYear ?? "N/A"}'),
                    ),
                    Text(p.experience, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () => showCompanionDetails(context, p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green, // Color Verde
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                          minimumSize: const Size(80, 30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Conocer', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: demoGroups.map((g) => _buildGroupCard(context, g)).toList(),
    );
  }

  Widget _buildGroupCard(BuildContext context, CommunityGroup group) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        leading: Icon(group.icon, color: Colors.purple, size: 30),
        title: Text(group.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(group.subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _GroupDetailScreen(group: group)),
        ),
      ),
    );
  }
}

class _GroupDetailScreen extends StatelessWidget {
  final CommunityGroup group;
  const _GroupDetailScreen({required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(group.title), backgroundColor: Colors.purple.shade100),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 200, width: double.infinity,
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.image, size: 100, color: Colors.purple),
          ),
          const SizedBox(height: 20),
          Text(group.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.purple)),
          Text(group.subtitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const Divider(height: 40),
          const SizedBox(height: 10),
          Text(group.description, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 20),
          const Text('Información de contacto:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Text(group.contact, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 40),
          ElevatedButton(onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6A1B9A), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
            child: const Text('← VOLVER'),
          ),
        ]),
      ),
    );
  }
}

class _LessonsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Lecciones de aprendizaje',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple)),
        const SizedBox(height: 15),
        ...demoLessons.map((l) => _buildLessonItem(context, l)),
      ],
    );
  }

  Widget _buildLessonItem(BuildContext context, CommunityLesson lesson) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        leading: const Icon(Icons.book, color: Colors.orange),
        title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(lesson.summary),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _LessonDetailScreen(title: lesson.title, content: lesson.content),
          ),
        ),
      ),
    );
  }
}


class _LessonDetailScreen extends StatelessWidget {
  final String title;
  final String content;

  const _LessonDetailScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lección'), backgroundColor: Colors.purple.shade100),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.purple)),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),
                  Text(content, style: const TextStyle(fontSize: 18, height: 1.5)),
                  const SizedBox(height: 40),
                  const Text('Datos relevantes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  const Text('• Mantenerse informado es clave para el tratamiento.\n• El apoyo familiar mejora la calidad de vida.'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text('← VOLVER', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
