import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:flutter/services.dart' show rootBundle;

class CardItem {
  final String imageUrl; // local path or remote url
  final String videoUrl; // local path or remote url
  CardItem({required this.imageUrl, required this.videoUrl});
}

void main() {
  runApp(const MemeTabuApp());
}

class MemeTabuApp extends StatelessWidget {
  const MemeTabuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Tabu',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00FFF6),
          secondary: const Color(0xFF8A2BE2),
        ),
      ),
      home: const PlayerSetupScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Player setup screen (dinamik oyuncu ekleme)
class PlayerSetupScreen extends StatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  State<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends State<PlayerSetupScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final List<String> _players = [];

  void _addPlayer() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _players.add(name);
      _nameCtrl.clear();
    });
  }

  Future<List<CardItem>> loadCards() async {
    // assets/cards.json içinde bir dizi JSON objesi bekliyoruz:
    // [{ "image": "path_or_url", "video": "path_or_url" }, ...]
    try {
      final data = await rootBundle.loadString('assets/cards.json');
      final List<dynamic> jsonList = json.decode(data);
      return jsonList
          .map(
            (jsonItem) => CardItem(
              imageUrl: (jsonItem['image'] ?? '').toString().trim(),
              videoUrl: (jsonItem['video'] ?? '').toString().trim(),
            ),
          )
          .toList();
    } catch (e) {
      // Eğer assets yoksa fallback hardcoded örnek
      return [
        CardItem(
          imageUrl: 'https://i.imgflip.com/30zz5g.jpg',
          videoUrl: 'https://www.w3schools.com/html/mov_bbb.mp4',
        ),
      ];
    }
  }

  void _startGame() async {
    if (_players.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('En az bir oyuncu ekleyin')));
      return;
    }
    final cards = await loadCards();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(players: _players, cards: cards),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neon = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oyuncu Ekranı'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Oyuncu adı',
                labelStyle: TextStyle(color: neon),
                suffixIcon: IconButton(
                  icon: Icon(Icons.add, color: neon),
                  onPressed: _addPlayer,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: neon.withOpacity(0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: neon),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _addPlayer(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _players
                  .map(
                    (p) => Chip(
                      label: Text(p),
                      backgroundColor: Colors.white10,
                      shape: StadiumBorder(
                        side: BorderSide(color: neon.withOpacity(0.6)),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: neon,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Oyunu Başlat', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Game screen: Video üstte, oyuncular altta (seçimin C)
class GameScreen extends StatefulWidget {
  final List<String> players;
  final List<CardItem> cards;
  const GameScreen({required this.players, required this.cards, super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int _index = 0;
  int _time = 10;
  String _phase = 'preVideo'; // 'preVideo' | 'video' | 'next'
  late List<int> _scores;
  VlcPlayerController? _vlcController;
  bool _videoReady = false;
  Timer? _positionPollTimer;
  vp.VideoPlayerController? _vpController;
  bool _vpInitialized = false;

  @override
  void initState() {
    super.initState();
    _scores = List<int>.filled(widget.players.length, 0);
    _prepareCard();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    if (_vlcController != null) {
      try {
        // stop() çağrılmadan önce initialized kontrol et
        if (_vlcController!.value.isInitialized) {
          _vlcController!.stop();
        }
      } catch (_) {}
      try {
        _vlcController!.dispose();
      } catch (_) {}
      _vlcController = null;
      _videoReady = false;
    }
    if (_vpController != null) {
      try {
        _vpController!.pause();
      } catch (_) {}
      try {
        _vpController!.dispose();
      } catch (_) {}
      _vpController = null;
      _vpInitialized = false;
    }
  }

  void _prepareCard() {
    _disposeVideo();
    setState(() {
      _time = 5; // ön-video bekleme süresi: 5s
      _phase = 'preVideo';
      _videoReady = false;
    });
    debugPrint('Prepare card index=$_index');
    _startPreVideoCountdown();
  }

  void _startPreVideoCountdown() {
    int remaining = 5;
    final current = widget.cards[_index];
    // Ön-video: önce video controller'ını hazırlanmış halde başlat (görüntü görünür ama oynamaz)
    _prepareVideo(current).whenComplete(() {
      // Sayaç başlasın
      Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _phase != 'preVideo') {
          t.cancel();
          return;
        }
        remaining--;
        setState(() {
          _time = remaining;
        });
        if (remaining <= 0) {
          t.cancel();
          // Sayaç bitti: oynatmayı başlat
          _beginPlayback();
        }
      });
    });
  }

  Future<void> _prepareVideo(CardItem current) async {
    // _disposeVideo() zaten _prepareCard'da çağrıldı.
    try {
      final videoPath = current.videoUrl.trim();
      final isUrl =
          videoPath.startsWith('http://') || videoPath.startsWith('https://');
      debugPrint('[_prepareVideo] index=$_index isUrl=$isUrl video=$videoPath');
      if (Platform.isWindows) {
        // video_player fallback için initialize et (hazır ama duraklatılmış)
        _vpController = isUrl
            ? vp.VideoPlayerController.network(videoPath)
            : vp.VideoPlayerController.file(File(videoPath));
        debugPrint(
          '[_prepareVideo] initialized vp controller for index=$_index',
        );
        await _vpController!.initialize();
        try {
          await _vpController!.pause();
        } catch (_) {}
        setState(() {
          _vpInitialized = true;
        });
      } else {
        // VLC yolu: controller oluştur, ama oynatma çağrısı yapma
        if (!isUrl) {
          final file = File(videoPath);
          if (!file.existsSync()) {
            debugPrint('[_prepareVideo] local file not found: $videoPath');
            throw Exception('Local video not found');
          }
        }
        if (isUrl) {
          _vlcController = VlcPlayerController.network(videoPath);
        } else {
          _vlcController = VlcPlayerController.file(File(videoPath));
        }
        debugPrint(
          '[_prepareVideo] initialized vlc controller for index=$_index',
        );
        // küçük bekleme ile plugin'in internal durumunu yakalamaya çalış
        await Future.delayed(const Duration(milliseconds: 300));
        setState(() {
          _videoReady = true;
        });
      }
    } catch (e) {
      debugPrint('Video hazırlama hatası: $e');
      // Hazırlık başarısızsa kullanıcıyı next aşamasına al
      if (mounted) {
        setState(() {
          _phase = 'next';
        });
      }
    }
  }

  void _beginPlayback() {
    if (!mounted) return;
    setState(() {
      _phase = 'video';
      _time = 5; // oynatma için gösterge
    });

    debugPrint('[_beginPlayback] index=$_index');

    // Eğer video_player hazırsa onu oynat
    if (_vpInitialized && _vpController != null) {
      try {
        _vpController!.play();
      } catch (e) {
        debugPrint('vp play hatası: $e');
      }
      // 5s sonra durdur ve ileri
      Timer(const Duration(seconds: 5), () async {
        try {
          await _vpController?.pause();
        } catch (_) {}
        try {
          await _vpController?.dispose();
        } catch (_) {}
        _vpController = null;
        _vpInitialized = false;
        if (mounted) _onVideoFinished();
      });
      return;
    }

    // VLC hazırsa onu oynat ve 5s sonra durdur
    if (_vlcController != null) {
      try {
        _vlcController!.play();
      } catch (e) {
        debugPrint('VLC play hatası: $e');
      }
      Timer(const Duration(seconds: 5), () async {
        try {
          await _vlcController?.stop();
        } catch (_) {}
        try {
          _vlcController?.dispose();
        } catch (_) {}
        _vlcController = null;
        _videoReady = false;
        if (mounted) _onVideoFinished();
      });
      return;
    }

    // Hiçbir controller yoksa doğrudan next'e geç
    setState(() {
      _phase = 'next';
    });
  }

  Future<void> _startVideo() async {
    final current = widget.cards[_index];
    setState(() {
      _phase = 'video';
      _time = 5; // video süresi: 5s
    });

    // On Windows the flutter_vlc_player may fail if native libvlc isn't available.
    // Prefer using the video_player fallback on Windows to avoid platform channel errors.
    if (Platform.isWindows) {
      debugPrint(
        'Platform Windows: VLC atlatılıyor, video_player fallback kullanılıyor',
      );
      await _startVideoFallback(current);
      return;
    }

    try {
      // local file mı yoksa network URL mi kontrol et
      final isUrl =
          current.videoUrl.startsWith('http://') ||
          current.videoUrl.startsWith('https://');

      if (isUrl) {
        // network kaynak
        _vlcController = VlcPlayerController.network(current.videoUrl);
      } else {
        // Windows local path örn: C:\Users\...\video.mp4
        final file = File(current.videoUrl);
        _vlcController = VlcPlayerController.file(file);
      }

      // küçük delay ile initialize çağır (plugin initialize implicit)
      // bazı sürümlerde initialize metodu yok; bu yüzden hazır olana kadar bekleyeceğiz
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        _videoReady = true;
      });

      // Oynatmayı post-frame olarak dene: controller hazırlanmış mı kontrol et
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_vlcController != null && _vlcController!.value.isInitialized) {
          try {
            await _vlcController?.play();
            debugPrint('VLC: play çağrıldı');
          } catch (e) {
            debugPrint('VLC play hatası: $e');
            // Fallback'e geç
            try {
              await _startVideoFallback(current);
            } catch (e2) {
              debugPrint('video_player fallback hatası: $e2');
              if (mounted) {
                setState(() {
                  _phase = 'next';
                });
              }
            }
          }
        } else {
          // Controller hazır değilse fallback'e geç
          debugPrint('VLC controller hazır değil, video_player ile denenecek');
          try {
            await _startVideoFallback(current);
          } catch (e) {
            debugPrint('video_player fallback hatası: $e');
            if (mounted) {
              setState(() {
                _phase = 'next';
              });
            }
          }
        }
      });

      // Video bitimini tespit etmek için periyodik pozisyon kontrolü yap
      _positionPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
        _,
      ) async {
        if (!mounted || _vlcController == null) {
          _positionPollTimer?.cancel();
          return;
        }
        try {
          final pos = await _vlcController!.getPosition();
          final dur = await _vlcController!.getDuration();
          if (dur is Duration) {
            final posMs = pos.inMilliseconds;
            final durMs = dur.inMilliseconds;
            if (durMs > 0 && posMs >= durMs - 500) {
              _positionPollTimer?.cancel();
              _onVideoFinished();
            }
          }
        } catch (e) {
          // bazı platformlarda getPosition/getDuration hata verebilir; ignore
        }
      });
    } catch (e) {
      // video başlatılamadıysa kullanıcıya 'Sonraki' aşamasını göster
      setState(() {
        _phase = 'next';
      });
      debugPrint('Video başlatma hatası: $e');
    }
  }

  void _onVideoFinished() {
    // video bittiğinde sonraki karta geç
    if (!mounted) return;
    if (_index + 1 < widget.cards.length) {
      setState(() {
        _index += 1;
      });
      _prepareCard();
    } else {
      _showGameOver();
    }
  }

  void _showGameOver() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF081018),
        title: const Text('Oyun Bitti', style: TextStyle(color: Colors.white)),
        content: Text(
          'Skorlar:\n' + _scoreText(),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  String _scoreText() {
    return List.generate(
      widget.players.length,
      (i) => '${widget.players[i]}: ${_scores[i]}',
    ).join('\n');
  }

  void _playerGotPoint(int i) {
    setState(() {
      _scores[i] += 1;
    });
  }

  void _forceNext() {
    _disposeVideo();
    if (_index + 1 < widget.cards.length) {
      setState(() {
        _index += 1;
      });
      _prepareCard();
    } else {
      _showGameOver();
    }
  }

  Future<void> _startVideoFallback(CardItem current) async {
    // video_player fallback: VLC başarısızsa bunu çağır
    try {
      final isUrl =
          current.videoUrl.startsWith('http://') ||
          current.videoUrl.startsWith('https://');
      if (isUrl) {
        _vpController = vp.VideoPlayerController.network(current.videoUrl);
      } else {
        _vpController = vp.VideoPlayerController.file(File(current.videoUrl));
      }
      await _vpController!.initialize();
      setState(() {
        _vpInitialized = true;
      });
      // 5 saniye oynat sonra geç
      await _vpController!.play();
      Timer(const Duration(seconds: 5), () async {
        try {
          await _vpController?.pause();
        } catch (_) {}
        try {
          await _vpController?.dispose();
        } catch (_) {}
        _vpController = null;
        _vpInitialized = false;
        if (mounted) _onVideoFinished();
      });
    } catch (e) {
      debugPrint('video_player fallback hatası: $e');
      if (mounted) {
        setState(() {
          _phase = 'next';
        });
      }
      rethrow;
    }
  }

  Widget _buildMediaArea(CardItem card, double width) {
    // Fotoğraf/video alanı yüksekliğini doğru hesapla (16:9 -> height = width * 9/16)
    final rawHeight = (width * (9 / 16));
    final screenHeight = MediaQuery.of(context).size.height;
    // limit: ekranın yarısından daha büyük olmasın
    final mediaHeight = rawHeight.clamp(0.0, screenHeight * 0.5);
    // Note: dikey videolar için BoxFit.cover ile yükseklik kullanıyoruz
    if (_phase == 'preVideo') {
      // PreVideo: video ekranda görünsün ama henüz oynatma başlamasın; üstte 5s sayaç overlay'i göster
      Widget content;
      if (_vpInitialized && _vpController != null) {
        content = vp.VideoPlayer(_vpController!);
      } else if (_vlcController != null && _videoReady) {
        content = VlcPlayer(
          controller: _vlcController!,
          aspectRatio: 9 / 16,
          placeholder: const Center(child: CircularProgressIndicator()),
        );
      } else {
        content = Container(color: Colors.black87);
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          height: mediaHeight,
          color: Colors.black87,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Container(color: Colors.black26),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_time',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 56 * ((width / 400).clamp(0.8, 1.6)),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_phase == 'video') {
      // Video aşaması: önce video_player fallback kontrol et
      if (_vpInitialized && _vpController != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: width,
            height: mediaHeight,
            color: Colors.black,
            child: vp.VideoPlayer(_vpController!),
          ),
        );
      }

      // Eğer VLC hazır değilse loading göster
      if (!_videoReady || _vlcController == null) {
        return SizedBox(
          width: width,
          height: mediaHeight,
          child: const Center(child: CircularProgressIndicator()),
        );
      }

      // VLC player alanı
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          height: mediaHeight,
          color: Colors.black,
          child: VlcPlayer(
            controller: _vlcController!,
            aspectRatio: 9 / 16, // dikey videolar için
            placeholder: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    } else {
      // next button phase: sadece Sonraki butonunu göster
      return SizedBox(
        width: width,
        height: mediaHeight,
        child: Center(
          child: ElevatedButton(
            onPressed: () {
              if (_index + 1 < widget.cards.length) {
                setState(() {
                  _index += 1;
                });
                _prepareCard();
              } else {
                _showGameOver();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
            ),
            child: const Text('Sonraki'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final neon = Theme.of(context).colorScheme.primary;
    final card = widget.cards[_index];
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final mediaWidth = (screenWidth - 28); // padding dikkate alındı
    // Responsive scale (400 is base width reference)
    final scale = (screenWidth / 400).clamp(0.8, 1.4);
    final playerAreaHeight = math.min(110.0, screenHeight * 0.18);
    final playerTileWidth = math.min(160.0, mediaWidth * 0.36);
    final fontSizeNormal = 16.0 * scale;
    final fontSizeScore = 22.0 * scale;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Oyun'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _forceNext,
            icon: Icon(Icons.skip_next, color: neon),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Üst: Tur + Süre
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tur: ${_index + 1}/${widget.cards.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: neon.withOpacity(0.8)),
                      ),
                      child: Text(
                        'Süre: $_time',
                        style: TextStyle(
                          color: neon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Media alanı (foto/video)
                _buildMediaArea(card, mediaWidth),

                const SizedBox(height: 12),

                // Oyuncu butonları (aşağıda)
                SizedBox(
                  height: playerAreaHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.players.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      return GestureDetector(
                        onTap: () => _playerGotPoint(i),
                        child: Container(
                          width: playerTileWidth,
                          padding: EdgeInsets.all(12 * scale),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [neon.withOpacity(0.12), Colors.white10],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: neon.withOpacity(0.7)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.players[i],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: fontSizeNormal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_scores[i]}',
                                style: TextStyle(
                                  color: neon,
                                  fontSize: fontSizeScore,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Kontroller
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _index = 0;
                          _scores = List<int>.filled(widget.players.length, 0);
                        });
                        _prepareCard();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neon.withOpacity(0.9),
                      ),
                      child: const Text('Yeniden Başlat'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                      ),
                      child: const Text('Çık'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
