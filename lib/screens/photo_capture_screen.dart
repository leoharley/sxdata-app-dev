import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';
import '../models/questionnaire.dart';
import '../providers/form_provider.dart';
import '../services/platform_caps.dart';
import '../services/location_service.dart';
import '../services/image_downscaler/image_downscaler.dart';
import '../services/web_media_store/web_media_store.dart';
import '../widgets/location_required_dialog.dart';
import 'form_completed_screen.dart';

class PhotoCaptureScreen extends StatefulWidget {
  final Questionnaire questionnaire;

  const PhotoCaptureScreen({super.key, required this.questionnaire});

  /// Questionário com "Requer foto" e formulário sem foto?
  ///
  /// Na edição não se exige foto nova: o entrevistado já não está presente,
  /// e vale a foto da entrevista original.
  @visibleForTesting
  static bool fotoObrigatoriaFaltando({
    required bool requiresPhoto,
    required bool isEditMode,
    String? photoPath,
  }) =>
      requiresPhoto &&
      !isEditMode &&
      (photoPath == null || photoPath.trim().isEmpty);

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  File? _capturedPhoto;
  File? _capturedPhoto2; // Segunda foto
  // Web: as fotos vivem em memória/IndexedDB (não há File no navegador)
  Uint8List? _capturedPhotoBytes;
  Uint8List? _capturedPhoto2Bytes;
  String? _photoFilename;
  String? _photo2Filename;
  Position? _currentPosition;

  bool get _hasPhoto1 => _capturedPhoto != null || _capturedPhotoBytes != null;
  bool get _hasPhoto2 =>
      _capturedPhoto2 != null || _capturedPhoto2Bytes != null;
  bool _isLoadingLocation = false;
  bool _isNavigating = false;
  final ImagePicker _picker = ImagePicker();

  /// Limites da foto de evidência.
  ///
  /// Sem eles a imagem vinha na resolução nativa da câmera (12 MP ≈
  /// 4000x3000). O JPEG até cabe na memória, mas para EXIBIR o preview o
  /// navegador descomprime para bitmap: 4000x3000x4 bytes ≈ 48 MB de uma
  /// vez. Em aparelho de 2 GB rodando no navegador isso derruba a aba.
  ///
  /// 1600x1200 (≈2 MP) descomprime para ~7,7 MB e continua legível de
  /// sobra para evidência de campo. O redimensionamento é feito pelo
  /// próprio image_picker, ANTES de os bytes chegarem ao app.
  static const double _maxPhotoWidth = 1600;
  static const double _maxPhotoHeight = 1600;
  static const int _photoQuality = 70;

  @override
  void initState() {
    super.initState();
    print('📸 PhotoCaptureScreen iniciado');
    print('📋 Questionnaire: ${widget.questionnaire.title}');
    print('📍 Requer localização: ${widget.questionnaire.requiresLocation}');
    print('📸 Requer foto: ${widget.questionnaire.requiresPhoto}');
    
    // Na edição não captura: a localização é a da entrevista original
    final isEditMode =
        Provider.of<FormProvider>(context, listen: false).isEditMode;
    if (widget.questionnaire.requiresLocation && !isEditMode) {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    // Libera os bytes das fotos ao sair da tela. Eles já estão salvos no
    // IndexedDB/arquivo; manter uma segunda cópia viva só pressiona a
    // memória de aparelhos fracos durante o resto do questionário.
    _capturedPhotoBytes = null;
    _capturedPhoto2Bytes = null;
    // O cache de imagens do Flutter guarda os bitmaps decodificados;
    // sem limpar, eles sobrevivem à tela.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header customizado com logo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botão voltar
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF23345F),
                      size: 24,
                    ),
                  ),
                  // Logo centralizado
                  Image.asset(
                    'assets/images/logo_socialx.png',
                    width: 120,             
                    fit: BoxFit.contain,
                  ),
                  // Ícone de câmera
                  const Icon(
                    Icons.camera_alt,
                    color: Color(0xFF8FAE5D),
                    size: 24,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const Text(
                              'Evidência Fotográfica',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF23345F),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              widget.questionnaire.requiresPhoto
                                  ? 'Foto obrigatória: tire a foto para finalizar'
                                  : 'Foto opcional para evidência',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 30),
                            
                            _buildPhotoCapture(),

                            if (_hasPhoto1) ...[
                              const SizedBox(height: 20),
                              _buildCapturedPhoto(),
                            ],

                            // Segunda foto (opcional)
                            const SizedBox(height: 20),
                            const Text(
                              'Evidência Fotográfica 2 (Opcional)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF23345F),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            _buildPhotoCapture2(),

                            if (_hasPhoto2) ...[
                              const SizedBox(height: 20),
                              _buildCapturedPhoto2(),
                            ],

                            if (widget.questionnaire.requiresLocation) ...[
                              const SizedBox(height: 20),
                              _buildLocationSection(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCapture() {
    return GestureDetector(
      onTap: _capturePhoto,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF8FAE5D),
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFF8FAF6),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt,
                size: 60,
                color: Color(0xFF8FAE5D),
              ),
              SizedBox(height: 15),
              Text(
                'Toque para capturar foto',
                style: TextStyle(
                  color: Color(0xFF8FAE5D),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'A foto será anexada ao formulário automaticamente',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCapture2() {
    return GestureDetector(
      onTap: _capturePhoto2,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF8FAE5D),
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFF8FAF6),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt,
                size: 60,
                color: Color(0xFF8FAE5D),
              ),
              SizedBox(height: 15),
              Text(
                'Toque para capturar segunda foto',
                style: TextStyle(
                  color: Color(0xFF8FAE5D),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Foto adicional para evidência (opcional)',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapturedPhoto() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF8FAE5D), size: 20),
              SizedBox(width: 8),
              Text(
                '📋 Foto capturada:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF23345F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                // O preview tem 120px de altura, mas sem ResizeImage o
                // bitmap é decodificado em resolução plena. Decodificar já
                // reduzido é o que mantém o uso de memória baixo em
                // aparelhos fracos.
                image: _thumb(_capturedPhotoBytes, _capturedPhoto),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg • ${((_capturedPhotoBytes?.length ?? _capturedPhoto!.lengthSync()) / (1024 * 1024)).toStringAsFixed(1)} MB',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedPhoto2() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF8FAE5D), size: 20),
                  SizedBox(width: 8),
                  Text(
                    '📋 Segunda foto capturada:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF23345F),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF8FAE5D)),
                onPressed: _retakePhoto2,
                tooltip: 'Refazer foto 2',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: _thumb(_capturedPhoto2Bytes, _capturedPhoto2),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'IMG2_${DateTime.now().millisecondsSinceEpoch}.jpg • ${((_capturedPhoto2Bytes?.length ?? _capturedPhoto2!.lengthSync()) / (1024 * 1024)).toStringAsFixed(1)} MB',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    final formProvider = Provider.of<FormProvider>(context, listen: false);
    if (formProvider.isEditMode) {
      // Edição não captura posição: mostra a que a entrevista registrou
      final form = formProvider.currentForm;
      final temCoordenadas = form?.latitude != null && form?.longitude != null;
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFF23345F), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                temCoordenadas
                    ? 'Localização da entrevista mantida: '
                        '${form!.latitude!.toStringAsFixed(4)}, '
                        '${form.longitude!.toStringAsFixed(4)}'
                    : 'A entrevista foi registrada sem localização. '
                        'A edição não altera a localização.',
                style: const TextStyle(color: Color(0xFF23345F), fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingLocation) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text(
              'Obtendo localização...',
              style: TextStyle(color: Colors.blue),
            ),
          ],
        ),
      );
    }

    if (_currentPosition != null) {
      return _buildLocationInfo();
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.location_off,
            color: Colors.orange,
            size: 24,
          ),
          const SizedBox(height: 5),
          const Text(
            'Localização não disponível',
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Verifique as permissões de localização',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _getCurrentLocation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            ),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFe3f2fd),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.location_on,
            color: Color(0xFF1976d2),
            size: 24,
          ),
          const SizedBox(height: 5),
          const Text(
            'Coordenadas registradas',
            style: TextStyle(
              color: Color(0xFF1976d2),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final formProvider = Provider.of<FormProvider>(context, listen: false);
    // Cinza quando falta a foto obrigatória. Continua tocável: o toque
    // explica o motivo em vez de o botão simplesmente não responder.
    final canFinish = !PhotoCaptureScreen.fotoObrigatoriaFaltando(
      requiresPhoto: widget.questionnaire.requiresPhoto,
      isEditMode: formProvider.isEditMode,
      photoPath: formProvider.currentForm?.photoPath,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          if (_hasPhoto1)
            Expanded(
              child: OutlinedButton(
                onPressed: _isNavigating ? null : _retakePhoto,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.grey),
                ),
                child: const Text(
                  'Refazer Foto',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),

          if (_hasPhoto1) const SizedBox(width: 10),

          Expanded(
            flex: _hasPhoto1 ? 2 : 1,
            child: ElevatedButton(
              //onPressed: _isNavigating ? null : (canFinish ? _completeForm : null),
              onPressed: _completeForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: canFinish ? const Color(0xFF8FAE5D) : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isNavigating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Finalizar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Substitua o método _capturePhoto na photo_capture_screen.dart:

  /// Provider de imagem para os previews, decodificando em tamanho reduzido.
  ///
  /// Sem o ResizeImage o Flutter decodifica a imagem inteira para o cache,
  /// mesmo o preview tendo 120px. Em aparelho fraco é o que estoura a
  /// memória logo após a captura.
  ImageProvider _thumb(Uint8List? bytes, File? file) {
    final ImageProvider base =
        bytes != null ? MemoryImage(bytes) : FileImage(file!);
    return ResizeImage(base, width: 640, allowUpscaling: false);
  }

  Future<void> _capturePhoto() async {
    print('📸 Tentando capturar foto');

    try {
      // Na web o prompt de câmera é do próprio navegador, no pickImage.
      final permission = PlatformCaps.hasPermissionHandler
          ? await Permission.camera.request()
          : PermissionStatus.granted;
      print('📸 Permissão de câmera: $permission');

      if (permission.isGranted) {
        // No NATIVO o plugin redimensiona de forma eficiente, então os
        // limites vão aqui. Na WEB eles são contraproducentes: o
        // image_picker_for_web carrega a imagem inteira num
        // HTMLImageElement (12 MP ≈ 48 MB) só para então reduzir — é o
        // pico que derruba celular fraco. Lá a redução é feita pelo
        // ImageDownscaler, com createImageBitmap.
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: PlatformCaps.isWeb ? null : _maxPhotoWidth,
          maxHeight: PlatformCaps.isWeb ? null : _maxPhotoHeight,
          imageQuality: PlatformCaps.isWeb ? null : _photoQuality,
        );

        if (photo != null) {
          print('📸 Foto capturada: ${photo.path}');

          if (PlatformCaps.isWeb) {
            // Web: reduzir ANTES de guardar. O createImageBitmap decodifica
            // já no tamanho final, sem materializar o bitmap de 12 MP.
            final brutos = await photo.readAsBytes();
            final bytes = await ImageDownscaler.downscale(
              brutos,
              maxDimension: _maxPhotoWidth.toInt(),
              quality: _photoQuality / 100,
            );
            // Foto vazia seria descartada como órfã na sincronização, e a
            // coleta chegaria ao painel citando um arquivo que nunca sobe.
            if (bytes.isEmpty) {
              _avisarFotoNaoAnexada();
              return;
            }
            final filename =
                'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
            // Foto anterior refeita? Remover a pendência órfã.
            if (_photoFilename != null) {
              await WebMediaStore.delete(_photoFilename!);
            }
            await WebMediaStore.save(
                filename: filename, bytes: bytes, kind: 'photo');
            if (!mounted) return;
            final anexada = Provider.of<FormProvider>(context, listen: false)
                .setPhoto(filename);
            if (!anexada) {
              await WebMediaStore.delete(filename);
              _avisarFotoNaoAnexada();
              return;
            }
            setState(() {
              _capturedPhotoBytes = bytes;
              _photoFilename = filename;
            });
            return;
          }

          if (!mounted) return;
          // A foto vai para a fila de envio na finalização
          // (FormProvider.submitFormWithPhoto); aqui só entra no formulário.
          final anexada = Provider.of<FormProvider>(context, listen: false)
              .setPhoto(photo.path);
          if (!anexada) {
            _avisarFotoNaoAnexada();
            return;
          }
          setState(() {
            _capturedPhoto = File(photo.path);
          });
          print('✅ Caminho da foto definido no FormProvider');
        } else {
          print('⚠️ Nenhuma foto foi capturada');
        }
      } else {
        print('❌ Permissão de câmera negada');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão de câmera necessária para capturar foto'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ Erro ao capturar foto: $e');
      print('📋 Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao capturar foto: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// A foto foi tirada mas não entrou no formulário: o aplicador precisa
  /// saber, senão finaliza achando que ela foi junto.
  void _avisarFotoNaoAnexada() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível anexar a foto. Tire a foto novamente.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _retakePhoto() {
    print('🔄 Refazendo foto');
    // Web: remover a pendência do IndexedDB para não subir foto órfã.
    if (_photoFilename != null) {
      WebMediaStore.delete(_photoFilename!);
    }
    // E tirar do formulário: se o aplicador finalizasse sem tirar outra, a
    // coleta citaria a foto descartada, que nunca chegaria ao painel.
    Provider.of<FormProvider>(context, listen: false).clearPhoto();
    setState(() {
      _capturedPhoto = null;
      _capturedPhotoBytes = null;
      _photoFilename = null;
    });
  }

  Future<void> _capturePhoto2() async {
    print('📸 Tentando capturar segunda foto');

    try {
      // Na web o prompt de câmera é do próprio navegador, no pickImage.
      final permission = PlatformCaps.hasPermissionHandler
          ? await Permission.camera.request()
          : PermissionStatus.granted;
      print('📸 Permissão de câmera: $permission');

      if (permission.isGranted) {
        // No NATIVO o plugin redimensiona de forma eficiente, então os
        // limites vão aqui. Na WEB eles são contraproducentes: o
        // image_picker_for_web carrega a imagem inteira num
        // HTMLImageElement (12 MP ≈ 48 MB) só para então reduzir — é o
        // pico que derruba celular fraco. Lá a redução é feita pelo
        // ImageDownscaler, com createImageBitmap.
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: PlatformCaps.isWeb ? null : _maxPhotoWidth,
          maxHeight: PlatformCaps.isWeb ? null : _maxPhotoHeight,
          imageQuality: PlatformCaps.isWeb ? null : _photoQuality,
        );

        if (photo != null) {
          print('📸 Segunda foto capturada: ${photo.path}');

          if (PlatformCaps.isWeb) {
            final brutos = await photo.readAsBytes();
            final bytes = await ImageDownscaler.downscale(
              brutos,
              maxDimension: _maxPhotoWidth.toInt(),
              quality: _photoQuality / 100,
            );
            if (bytes.isEmpty) {
              _avisarFotoNaoAnexada();
              return;
            }
            final filename =
                'photo2_${DateTime.now().millisecondsSinceEpoch}.jpg';
            if (_photo2Filename != null) {
              await WebMediaStore.delete(_photo2Filename!);
            }
            await WebMediaStore.save(
                filename: filename, bytes: bytes, kind: 'photo');
            if (!mounted) return;
            final anexada = Provider.of<FormProvider>(context, listen: false)
                .setPhoto2(filename);
            if (!anexada) {
              await WebMediaStore.delete(filename);
              _avisarFotoNaoAnexada();
              return;
            }
            setState(() {
              _capturedPhoto2Bytes = bytes;
              _photo2Filename = filename;
            });
            return;
          }

          if (!mounted) return;
          final anexada = Provider.of<FormProvider>(context, listen: false)
              .setPhoto2(photo.path);
          if (!anexada) {
            _avisarFotoNaoAnexada();
            return;
          }
          setState(() {
            _capturedPhoto2 = File(photo.path);
          });
          print('✅ Caminho da segunda foto definido no FormProvider');
        } else {
          print('⚠️ Nenhuma segunda foto foi capturada');
        }
      } else {
        print('❌ Permissão de câmera negada');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão de câmera necessária para capturar foto'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ Erro ao capturar segunda foto: $e');
      print('📋 Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao capturar segunda foto: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _retakePhoto2() {
    print('🔄 Refazendo segunda foto');
    // Web: remover a pendência do IndexedDB para não subir foto órfã.
    if (_photo2Filename != null) {
      WebMediaStore.delete(_photo2Filename!);
    }
    Provider.of<FormProvider>(context, listen: false).clearPhoto2();
    setState(() {
      _capturedPhoto2 = null;
      _capturedPhoto2Bytes = null;
      _photo2Filename = null;
    });
  }

  /// Garante que há coordenadas gravadas no formulário antes de finalizar.
  /// Tenta capturar em laço: a cada falha explica o motivo e oferece nova
  /// tentativa. Retorna false apenas se o aplicador voltar sem finalizar —
  /// se ele optar por concluir sem sinal, o formulário segue marcado como
  /// "Sem localização".
  Future<bool> _ensureLocationOrBlock() async {
    final formProvider = Provider.of<FormProvider>(context, listen: false);

    // Edição não exige nem captura localização: vale a da entrevista
    if (formProvider.isEditMode) {
      return true;
    }

    while (true) {
      if (formProvider.currentForm?.latitude != null) {
        print('📍 Localização já registrada no formulário');
        return true;
      }

      final motivo = await _tryCaptureLocation(formProvider);
      if (motivo == null) return true;

      if (!mounted) return false;
      final decisao = await showLocationRequiredDialog(context, motivo);

      switch (decisao) {
        case LocationDialogAction.retry:
          continue;
        case LocationDialogAction.finishWithout:
          formProvider.markLocationUnavailable();
          print('📍 Finalizando sem coordenadas por decisão do aplicador');
          return true;
        case LocationDialogAction.cancel:
        case null:
          print('📍 Aplicador cancelou — não finalizou');
          return false;
      }
    }
  }

  /// Uma tentativa de captura. Retorna null em caso de sucesso, ou o motivo
  /// da falha já escrito para o aplicador.
  ///
  /// A estratégia em etapas — e o motivo de cada uma — está em
  /// [LocationService.obterPosicao].
  Future<String?> _tryCaptureLocation(FormProvider formProvider) async {
    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
      });
    }

    try {
      final resultado = await LocationService.obterPosicao();

      if (resultado.ok) {
        final p = resultado.position!;
        formProvider.setLocation(p.latitude, p.longitude, '');
        if (mounted) {
          setState(() {
            _currentPosition = p;
          });
        }
        return null;
      }
      return resultado.erro;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  /// Botão manual de localização desta tela. Usa a mesma escada de tentativas
  /// da finalização, para não haver dois comportamentos diferentes de captura
  /// no mesmo aplicativo.
  Future<void> _getCurrentLocation() async {
    print('📍 Tentando obter localização');

    final formProvider = Provider.of<FormProvider>(context, listen: false);
    final motivo = await _tryCaptureLocation(formProvider);

    if (motivo != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(motivo),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _completeForm() async {
    print('🏁 Finalizando formulário');

    if (_isNavigating) {
      print('⚠️ Já está navegando, ignorando');
      return;
    }

    // "Requer foto" no painel: não finaliza sem foto. A referência é a foto
    // do FORMULÁRIO (vale no Android e na web), não o estado desta tela.
    final fotoProvider = Provider.of<FormProvider>(context, listen: false);
    if (PhotoCaptureScreen.fotoObrigatoriaFaltando(
      requiresPhoto: widget.questionnaire.requiresPhoto,
      isEditMode: fotoProvider.isEditMode,
      photoPath: fotoProvider.currentForm?.photoPath,
    )) {
      print('❌ Foto obrigatória não registrada');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este questionário exige foto. Tire a foto para finalizar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Localização obrigatória: não deixa finalizar sem coordenadas gravadas.
    // Tenta capturar em laço, explicando a falha e oferecendo nova tentativa.
    if (widget.questionnaire.requiresLocation) {
      final temLocalizacao = await _ensureLocationOrBlock();
      if (!temLocalizacao) {
        print('📍 Finalização bloqueada: sem localização capturada');
        return;
      }
    }

    setState(() {
      _isNavigating = true;
    });

    try {
      final formProvider = Provider.of<FormProvider>(context, listen: false);

      print('📤 ========================================');
      print('📤 === SUBMETENDO FORMULÁRIO COM FOTO ===');
      print('📤 ========================================');
      print('✏️ Modo de edição: ${formProvider.isEditMode}');
      print('✏️ ID do formulário em edição: ${formProvider.editingFormId}');
      print('📋 ID do formulário atual: ${formProvider.currentForm?.id}');
      print('📸 Foto capturada: ${_capturedPhoto?.path}');

      // SUBMETER O FORMULÁRIO ANTES DE NAVEGAR
      bool success = await formProvider.submitFormWithPhoto(null);

      if (!success) {
        print('❌ Falha ao submeter formulário com foto');
        setState(() {
          _isNavigating = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(formProvider.submitError ??
                  (formProvider.isEditMode
                      ? 'Erro ao atualizar formulário. Tente novamente.'
                      : 'Erro ao salvar formulário. Tente novamente.')),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      print('✅ Formulário com foto submetido com sucesso!');
      print('🔄 Navegando para FormCompletedScreen');

      // Debug do FormProvider após submissão
      formProvider.debugPrintCurrentState();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FormCompletedScreen(
            questionnaire: widget.questionnaire,
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('❌ Erro ao finalizar com foto: $e');
      print('📋 Stack trace: $stackTrace');

      setState(() {
        _isNavigating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}