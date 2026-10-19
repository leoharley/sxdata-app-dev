import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../services/platform_caps.dart';
import '../services/web_media_store/web_media_store.dart';

class PhotoStorageService {
  static const String _photosMetadataKey = 'offline_photos_metadata';
  static const String _photosFolderName = 'offline_photos';

  /// Salva uma foto localmente para sincronização posterior
  /// [photoType] pode ser 'photo1' ou 'photo2' para identificar qual foto é
  static Future<String> savePhotoOffline(File originalPhoto, int formId, {String photoType = 'photo1'}) async {
    try {
      print('📸 === SALVANDO FOTO OFFLINE ===');
      print('📸 Form ID: $formId');
      print('📸 Tipo de foto: $photoType');
      print('📸 Foto original: ${originalPhoto.path}');

      // Obter diretório de documentos da aplicação
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory photosDir = Directory('${appDocDir.path}/$_photosFolderName');

      // Criar diretório se não existir
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
        print('📸 Diretório criado: ${photosDir.path}');
      }

      // Gerar nome único para a foto incluindo o tipo
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String extension = originalPhoto.path.split('.').last;
      final String filename = 'form_${formId}_${photoType}_${timestamp}.$extension';
      final String localPath = '${photosDir.path}/$filename';

      // Copiar foto para diretório local
      final File localPhoto = await originalPhoto.copy(localPath);
      print('📸 Foto copiada para: ${localPhoto.path}');

      // Salvar metadados da foto
      await _savePhotoMetadata(formId, filename, localPath, photoType: photoType);

      print('✅ Foto salva offline com sucesso');
      return filename; // Retorna apenas o filename para salvar no formulário

    } catch (e, stackTrace) {
      print('❌ Erro ao salvar foto offline: $e');
      print('📋 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Salva metadados da foto no SharedPreferences
  static Future<void> _savePhotoMetadata(int formId, String filename, String localPath, {String photoType = 'photo1'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Carregar metadados existentes
      List<Map<String, dynamic>> photosMetadata = [];
      final String? existingData = prefs.getString(_photosMetadataKey);

      if (existingData != null) {
        final List<dynamic> existingList = jsonDecode(existingData);
        photosMetadata = existingList.cast<Map<String, dynamic>>();
      }

      // Adicionar nova foto
      final Map<String, dynamic> photoMetadata = {
        'formId': formId,
        'filename': filename,
        'localPath': localPath,
        'photoType': photoType, // Adiciona o tipo da foto
        'syncStatus': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
        'fileSize': await File(localPath).length(),
      };

      photosMetadata.add(photoMetadata);

      // Salvar de volta
      final String jsonData = jsonEncode(photosMetadata);
      await prefs.setString(_photosMetadataKey, jsonData);

      print('📸 Metadados da foto salvos: $photoMetadata');

    } catch (e) {
      print('❌ Erro ao salvar metadados da foto: $e');
      rethrow;
    }
  }

  /// Obtém todas as fotos pendentes de sincronização
  static Future<List<Map<String, dynamic>>> getPendingPhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);
      
      if (data == null) {
        return [];
      }
      
      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();
      
      // Pendentes E com falha de envio ('error'), desde que o arquivo exista.
      //
      // Antes só 'pending' era reenviada: uma foto que falhasse uma vez
      // (sem sinal, erro do servidor) nunca mais subia. E como a trava de
      // envio contava 'error' como pendente, ela segurava as coletas para
      // sempre. Arquivo que sumiu do aparelho vira 'lost': não há o que
      // enviar, e ele não pode prender coleta nenhuma.
      final List<Map<String, dynamic>> pendingPhotos = [];
      bool changed = false;

      for (final photo in photosMetadata) {
        final status = photo['syncStatus'];
        if (status != 'pending' && status != 'error') continue;

        final File photoFile = File(photo['localPath']);
        if (await photoFile.exists()) {
          pendingPhotos.add(photo);
        } else {
          print('⚠️ Foto não encontrada: ${photo['localPath']}');
          photo['syncStatus'] = 'lost';
          photo['errorMessage'] = 'Arquivo não encontrado no aparelho';
          changed = true;
        }
      }

      if (changed) {
        await prefs.setString(_photosMetadataKey, jsonEncode(photosMetadata));
      }
      
      print('📸 Fotos pendentes encontradas: ${pendingPhotos.length}');
      return pendingPhotos;
      
    } catch (e) {
      print('❌ Erro ao obter fotos pendentes: $e');
      return [];
    }
  }

  /// Nomes das fotos que ainda precisam subir (arquivo no aparelho e envio
  /// pendente ou com falha). Usado para segurar só a coleta que as cita.
  static Future<Set<String>> pendingFilenames() async {
    if (!PlatformCaps.hasFileSystem) return <String>{};
    final pending = await getPendingPhotos();
    return pending.map((p) => p['filename'].toString()).toSet();
  }

  /// Devolve à fila uma foto que o servidor diz não ter recebido.
  /// Retorna true se o arquivo ainda está no aparelho (vai subir de novo).
  static Future<bool> requeue(String filename) async {
    if (!PlatformCaps.hasFileSystem) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);
      if (data == null) return false;

      final photosMetadata =
          (jsonDecode(data) as List<dynamic>).cast<Map<String, dynamic>>();
      for (final photo in photosMetadata) {
        if (photo['filename'] != filename) continue;
        if (!await File(photo['localPath']).exists()) return false;
        photo['syncStatus'] = 'pending';
        photo['errorMessage'] = 'Servidor não tinha o arquivo; reenviando';
        await prefs.setString(_photosMetadataKey, jsonEncode(photosMetadata));
        print('📸 $filename de volta à fila de envio');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Erro ao reenfileirar foto $filename: $e');
      return false;
    }
  }

  static Future<void> _renameInMetadata(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_photosMetadataKey);
    if (data == null) return;
    final photosMetadata =
        (jsonDecode(data) as List<dynamic>).cast<Map<String, dynamic>>();
    for (final photo in photosMetadata) {
      if (photo['filename'] == oldName) photo['filename'] = newName;
    }
    await prefs.setString(_photosMetadataKey, jsonEncode(photosMetadata));
  }

  /// Atualiza o status de sincronização de uma foto
  static Future<void> updatePhotoSyncStatus(String filename, String status, {String? errorMessage}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);
      
      if (data == null) return;
      
      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();
      
      // Encontrar e atualizar a foto
      for (final photo in photosMetadata) {
        if (photo['filename'] == filename) {
          photo['syncStatus'] = status;
          photo['syncedAt'] = DateTime.now().toIso8601String();
          
          if (errorMessage != null) {
            photo['errorMessage'] = errorMessage;
          }
          
          print('📸 Status da foto $filename atualizado para: $status');
          break;
        }
      }
      
      // Salvar de volta
      await prefs.setString(_photosMetadataKey, jsonEncode(photosMetadata));
      
    } catch (e) {
      print('❌ Erro ao atualizar status da foto: $e');
    }
  }

  /// Remove foto local após sincronização bem-sucedida
  static Future<void> removePhotoAfterSync(String filename) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);
      
      if (data == null) return;
      
      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();
      
      // Encontrar foto e remover arquivo
      photosMetadata.removeWhere((photo) {
        if (photo['filename'] == filename && photo['syncStatus'] == 'synced') {
          // Remover arquivo local
          final File photoFile = File(photo['localPath']);
          if (photoFile.existsSync()) {
            photoFile.deleteSync();
            print('📸 Arquivo local removido: ${photo['localPath']}');
          }
          return true; // Remove da lista
        }
        return false;
      });
      
      // Salvar lista atualizada
      await prefs.setString(_photosMetadataKey, jsonEncode(photosMetadata));
      
    } catch (e) {
      print('❌ Erro ao remover foto: $e');
    }
  }

  /// Obtém o caminho local de uma foto pelo filename
  static Future<String?> getPhotoLocalPath(String filename) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);
      
      if (data == null) return null;
      
      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();
      
      for (final photo in photosMetadata) {
        if (photo['filename'] == filename) {
          final String localPath = photo['localPath'];
          final File photoFile = File(localPath);
          
          if (await photoFile.exists()) {
            return localPath;
          } else {
            print('⚠️ Arquivo não encontrado: $localPath');
            return null;
          }
        }
      }
      
      return null;
      
    } catch (e) {
      print('❌ Erro ao obter caminho da foto: $e');
      return null;
    }
  }

  /// Debug: Lista todas as fotos salvas
  static Future<void> debugPrintPhotos() async {
    try {
      print('📸 === DEBUG FOTOS OFFLINE ===');
      
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);
      
      if (data == null) {
        print('📸 Nenhuma foto encontrada');
        return;
      }
      
      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();
      
      print('📸 Total de fotos: ${photosMetadata.length}');
      
      for (int i = 0; i < photosMetadata.length; i++) {
        final photo = photosMetadata[i];
        final File photoFile = File(photo['localPath']);
        final bool exists = await photoFile.exists();
        
        print('📸 [$i] ${photo['filename']}:');
        print('   - Form ID: ${photo['formId']}');
        print('   - Status: ${photo['syncStatus']}');
        print('   - Arquivo existe: $exists');
        print('   - Tamanho: ${photo['fileSize']} bytes');
        print('   - Criado em: ${photo['createdAt']}');
        
        if (photo.containsKey('errorMessage')) {
          print('   - Erro: ${photo['errorMessage']}');
        }
      }
      
      // Verificar diretório de fotos
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory photosDir = Directory('${appDocDir.path}/$_photosFolderName');
      
      print('📸 Diretório de fotos: ${photosDir.path}');
      print('📸 Diretório existe: ${await photosDir.exists()}');
      
      if (await photosDir.exists()) {
        final List<FileSystemEntity> files = await photosDir.list().toList();
        print('📸 Arquivos no diretório: ${files.length}');
        
        for (final file in files) {
          if (file is File) {
            final int size = await file.length();
            print('   - ${file.path.split('/').last}: ${size} bytes');
          }
        }
      }
      
      print('📸 === FIM DEBUG FOTOS ===');
      
    } catch (e) {
      print('❌ Erro no debug de fotos: $e');
    }
  }

  /// Limpa todas as fotos offline (para desenvolvimento)
  static Future<void> clearAllOfflinePhotos() async {
    try {
      print('🧹 Limpando todas as fotos offline...');
      
      // Remover metadados
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_photosMetadataKey);
      
      // Remover diretório de fotos
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory photosDir = Directory('${appDocDir.path}/$_photosFolderName');
      
      if (await photosDir.exists()) {
        await photosDir.delete(recursive: true);
        print('🧹 Diretório de fotos removido');
      }
      
      print('✅ Todas as fotos offline foram removidas');
      
    } catch (e) {
      print('❌ Erro ao limpar fotos offline: $e');
    }
  }

  /// Obtém estatísticas das fotos offline
  static Future<Map<String, int>> getPhotosStats() async {
    try {
      // WEB: as fotos vivem no IndexedDB (WebMediaStore), não nesta chave de
      // metadados — que só é escrita no fluxo nativo. Sem este ramo a tela
      // mostrava "0 fotos" com foto capturada, e a trava que impede enviar
      // formulário com mídia pendente nunca disparava na web.
      if (!PlatformCaps.hasFileSystem) {
        final pendentes = await WebMediaStore.pendingCount('photo');
        return {
          'total': pendentes,
          'pending': pendentes,
          'synced': 0,
          'error': 0,
          'photo1_pending': pendentes,
          'photo2_pending': 0,
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);

      if (data == null) {
        return {
          'total': 0,
          'pending': 0,
          'synced': 0,
          'error': 0,
          'photo1_pending': 0,
          'photo2_pending': 0,
        };
      }

      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();

      int total = photosMetadata.length;
      int pending = 0;
      int synced = 0;
      int error = 0;
      int photo1Pending = 0;
      int photo2Pending = 0;

      for (final photo in photosMetadata) {
        switch (photo['syncStatus']) {
          case 'pending':
            pending++;
            // Contar por tipo de foto
            final photoType = photo['photoType'] ?? 'photo1';
            if (photoType == 'photo1') {
              photo1Pending++;
            } else if (photoType == 'photo2') {
              photo2Pending++;
            }
            break;
          case 'synced':
            synced++;
            break;
          case 'error':
            error++;
            break;
        }
      }

      return {
        'total': total,
        'pending': pending,
        'synced': synced,
        'error': error,
        'photo1_pending': photo1Pending,
        'photo2_pending': photo2Pending,
      };

    } catch (e) {
      print('❌ Erro ao obter estatísticas das fotos: $e');
      return {
        'total': 0,
        'pending': 0,
        'synced': 0,
        'error': 0,
        'photo1_pending': 0,
        'photo2_pending': 0,
      };
    }
  }

  /// Redefine o status de TODAS as fotos para 'pending' (para forçar reenvio)
  static Future<int> resetAllPhotosToPending() async {
    try {
      print('🔄 === REDEFININDO TODAS AS FOTOS PARA PENDENTE ===');

      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_photosMetadataKey);

      if (data == null) {
        print('📸 Nenhuma foto encontrada');
        return 0;
      }

      final List<dynamic> photosList = jsonDecode(data);
      final List<Map<String, dynamic>> photosMetadata = photosList.cast<Map<String, dynamic>>();

      int resetCount = 0;

      // Redefinir todas as fotos para 'pending' se o arquivo ainda existir
      for (final photo in photosMetadata) {
        final String localPath = photo['localPath'];
        final File photoFile = File(localPath);

        if (await photoFile.exists()) {
          // Só redefine se o arquivo existe
          photo['syncStatus'] = 'pending';
          photo['resetAt'] = DateTime.now().toIso8601String();

          // Remover mensagem de erro anterior se houver
          photo.remove('errorMessage');
          photo.remove('syncedAt');

          resetCount++;
          print('🔄 Foto ${photo['filename']} redefinida para pendente');
        } else {
          // Se arquivo não existe, marcar como erro
          photo['syncStatus'] = 'error';
          photo['errorMessage'] = 'Arquivo não encontrado no dispositivo';
          print('❌ Foto ${photo['filename']} não encontrada: $localPath');
        }
      }

      // Salvar metadados atualizados
      await prefs.setString(_photosMetadataKey, jsonEncode(photosMetadata));

      print('✅ $resetCount fotos redefinidas para pendente');
      return resetCount;

    } catch (e, stackTrace) {
      print('❌ Erro ao redefinir status das fotos: $e');
      print('📋 Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Sincroniza todas as fotos pendentes com o servidor
  static Future<int> syncPendingPhotos() async {
    // Web: fotos offline em arquivo não existem — o MediaStore (IndexedDB)
    // assume na Fase 2 do plano web (docs/plano_versao_web.md).
    if (!PlatformCaps.hasFileSystem) return 0;

    try {
      print('📸 === SINCRONIZANDO FOTOS PENDENTES ===');
      
      final List<Map<String, dynamic>> pendingPhotos = await getPendingPhotos();
      print('📸 ${pendingPhotos.length} fotos pendentes para sincronizar');
      
      int syncedCount = 0;
      
      for (final photoMetadata in pendingPhotos) {
        try {
          final String filename = photoMetadata['filename'];
          final String localPath = photoMetadata['localPath'];
          final File photoFile = File(localPath);
          
          if (!await photoFile.exists()) {
            print('❌ Arquivo não encontrado: $localPath');
            await updatePhotoSyncStatus(filename, 'error', errorMessage: 'Arquivo não encontrado');
            continue;
          }
          
          print('📤 Enviando foto: $filename');
          
          // Enviar foto usando ApiService
          final Map<String, dynamic> result = await ApiService.uploadPhoto(photoFile);
          
          if (result.containsKey('filename') || result.containsKey('file_name') ||
              result.containsKey('name') || result.containsKey('path')) {
            // Upload bem-sucedido. Se o servidor gravou com outro nome, as
            // coletas passam a citar esse nome — senão o painel não acha a foto.
            final serverName =
                (result['filename'] ?? result['file_name'])?.toString();
            if (serverName != null &&
                serverName.isNotEmpty &&
                serverName != filename) {
              await LocalStorageService.replaceMediaReference(
                  filename, serverName);
              await _renameInMetadata(filename, serverName);
              await updatePhotoSyncStatus(serverName, 'synced');
            } else {
              await updatePhotoSyncStatus(filename, 'synced');
            }
            syncedCount++;
            print('✅ Foto $filename sincronizada com sucesso');
            
            // Opcional: remover arquivo local após sincronização
            // await removePhotoAfterSync(filename);
            
          } else {
            print('❌ Resposta inválida do servidor para foto $filename');
            await updatePhotoSyncStatus(filename, 'error', 
                errorMessage: 'Resposta inválida do servidor');
          }
          
        } catch (e) {
          print('❌ Erro ao sincronizar foto ${photoMetadata['filename']}: $e');
          await updatePhotoSyncStatus(photoMetadata['filename'], 'error', 
              errorMessage: e.toString());
        }
      }
      
      print('✅ Sincronização de fotos concluída: $syncedCount de ${pendingPhotos.length}');
      return syncedCount;
      
    } catch (e, stackTrace) {
      print('❌ Erro durante sincronização de fotos: $e');
      print('📋 Stack trace: $stackTrace');
      return 0;
    }
  }
}