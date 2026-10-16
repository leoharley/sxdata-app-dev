import 'package:flutter/material.dart';
import '../models/question.dart';
import '../utils/phone_format.dart';

class QuestionWidget extends StatefulWidget {
  final Question question;
  final dynamic initialValue;
  final Function(dynamic) onChanged;

  const QuestionWidget({
    super.key,
    required this.question,
    this.initialValue,
    required this.onChanged,
  });

  @override
  State<QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<QuestionWidget> {
  // Variável para controlar o valor selecionado do radio
  String? _selectedRadioValue;
  List<String> _selectedCheckboxValues = [];

  @override
  void initState() {
    super.initState();
    print('QuestionWidget iniciado para tipo: ${widget.question.questionType}');
    
    // Inicializar valores baseado no tipo de questão
    if (widget.question.questionType.toLowerCase() == 'radio') {
      _selectedRadioValue = widget.initialValue?.toString();
    } else if (widget.question.questionType.toLowerCase() == 'checkbox') {
      if (widget.initialValue != null) {
        if (widget.initialValue is List) {
          _selectedCheckboxValues = List<String>.from(widget.initialValue);
        } else if (widget.initialValue is String) {
          _selectedCheckboxValues = [widget.initialValue];
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🏗️ QuestionWidget build');
    print('📝 Question type: ${widget.question.questionType}');
    print('📝 Question text: ${widget.question.questionText}');
    print('📝 Options count: ${widget.question.options.length}');
    print('📝 Initial value: ${widget.initialValue}');
    
    final questionType = widget.question.questionType.toLowerCase().trim();
    print('📝 Processed question type: "$questionType"');
    
    switch (questionType) {
      case 'text':
        print('🔤 Building text input');
        return _buildTextInput();
      case 'textarea':
        print('📄 Building textarea input');
        return _buildTextAreaInput();
      case 'number':
        print('🔢 Building number input');
        return _buildNumberInput();
      case 'phone':
        print('📞 Building phone input');
        return _buildPhoneInput();
      case 'date':
        print('📅 Building date input');
        return _buildDateInput();
      case 'datetime':
        print('🕐 Building datetime input');
        return _buildDateTimeInput();
      case 'radio':
        print('🔘 Building radio options');
        return _buildRadioOptions();
      case 'checkbox':
        print('☑️ Building checkbox options');
        return _buildCheckboxOptions();
      default:
        print('⚠️ Tipo não reconhecido: "$questionType", usando text input');
        return _buildTextInput();
    }
  }

Widget _buildTextInput() {
    const int maxCharacters = 500;
    
    return StatefulBuilder(
      builder: (context, setStateLocal) {
        final TextEditingController controller = TextEditingController();
        String currentText = widget.initialValue?.toString() ?? '';
        
        // Definir o texto inicial sem afetar a posição do cursor
        if (controller.text.isEmpty && currentText.isNotEmpty) {
          controller.text = currentText;
        }
        
        int currentLength = controller.text.length;
        int remainingCharacters = maxCharacters - currentLength;
        
        return Column(
          children: [
            // Contador personalizado na parte superior
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Contador de caracteres restantes
                  Text(
                    remainingCharacters >= 0 
                        ? '$remainingCharacters caracteres restantes'
                        : 'Excedeu em ${remainingCharacters.abs()} caracteres',
                    style: TextStyle(
                      fontSize: 12,
                      color: remainingCharacters >= 0 
                          ? (remainingCharacters < 50 ? Colors.orange : Colors.grey.shade600)
                          : Colors.red,
                      fontWeight: remainingCharacters < 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  
                  // Contador atual/máximo
                  Text(
                    '$currentLength/$maxCharacters',
                    style: TextStyle(
                      fontSize: 12,
                      color: remainingCharacters >= 0 
                          ? (remainingCharacters < 50 ? Colors.orange : Colors.grey.shade600)
                          : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: TextFormField(
                initialValue: widget.initialValue?.toString(),
                onChanged: (value) {
                  setStateLocal(() {}); // Atualiza o contador em tempo real
                  widget.onChanged(value);
                },
                maxLength: maxCharacters,
                decoration: InputDecoration(
                  hintText: 'Digite sua resposta aqui...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF8FAE5D), width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  // Remove o contador padrão do Flutter
                  counterText: '',
                ),
                validator: widget.question.isRequired
                    ? (value) => value?.isEmpty == true ? 'Campo obrigatório' : null
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextAreaInput() {
    const int maxCharacters = 500;
    
    return StatefulBuilder(
      builder: (context, setStateLocal) {
        String currentText = widget.initialValue?.toString() ?? '';
        int currentLength = currentText.length;
        int remainingCharacters = maxCharacters - currentLength;
        
        return Column(
          children: [
            // Contador personalizado na parte superior
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Contador de caracteres restantes
                  Text(
                    remainingCharacters >= 0 
                        ? '$remainingCharacters caracteres restantes'
                        : 'Excedeu em ${remainingCharacters.abs()} caracteres',
                    style: TextStyle(
                      fontSize: 12,
                      color: remainingCharacters >= 0 
                          ? (remainingCharacters < 50 ? Colors.orange : Colors.grey.shade600)
                          : Colors.red,
                      fontWeight: remainingCharacters < 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  
                  // Contador atual/máximo
                  Text(
                    '$currentLength/$maxCharacters',
                    style: TextStyle(
                      fontSize: 12,
                      color: remainingCharacters >= 0 
                          ? (remainingCharacters < 50 ? Colors.orange : Colors.grey.shade600)
                          : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: TextFormField(
                initialValue: widget.initialValue?.toString(),
                onChanged: (value) {
                  currentText = value;
                  currentLength = value.length;
                  setStateLocal(() {}); // Atualiza o contador em tempo real
                  widget.onChanged(value);
                },
                maxLines: 6,
                maxLength: maxCharacters,
                decoration: InputDecoration(
                  hintText: 'Digite sua resposta aqui...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF8FAE5D), width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  // Remove o contador padrão do Flutter
                  counterText: '',
                ),
                validator: widget.question.isRequired
                    ? (value) => value?.isEmpty == true ? 'Campo obrigatório' : null
                    : null,
              ),
            ),
            
            const SizedBox(height: 15),
            
            // Dica existente
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.grey, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dica: Seja específico e detalhado em sua resposta',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNumberInput() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextFormField(
        initialValue: widget.initialValue?.toString(),
        onChanged: (value) {
          final numValue = double.tryParse(value);
          widget.onChanged(numValue);
        },
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          hintText: 'Ex: 35',
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF8FAE5D), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        ),
        validator: widget.question.isRequired
            ? (value) => value?.isEmpty == true ? 'Campo obrigatório' : null
            : null,
      ),
    );
  }

  /// Telefone com DDD, mascarado enquanto digita: (00) 00000-0000.
  /// O valor guardado é o texto já formatado; a tela de perguntas não deixa
  /// avançar com o número pela metade (ver _canAdvanceFromCurrentQuestion).
  Widget _buildPhoneInput() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextFormField(
        initialValue: formatPhone(widget.initialValue?.toString() ?? ''),
        onChanged: (value) => widget.onChanged(value),
        keyboardType: TextInputType.phone,
        inputFormatters: [PhoneInputFormatter()],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          hintText: '(00) 00000-0000',
          hintStyle: TextStyle(color: Colors.grey.shade500),
          prefixIcon: Icon(Icons.phone, color: Colors.grey.shade600),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF8FAE5D), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        ),
        validator: (value) {
          final text = value ?? '';
          if (text.isEmpty) {
            return widget.question.isRequired ? 'Campo obrigatório' : null;
          }
          return isValidPhone(text) ? null : 'Informe o telefone com DDD';
        },
      ),
    );
  }

  Widget _buildDateInput() {
    DateTime? selectedDate;
    
    if (widget.initialValue != null) {
      if (widget.initialValue is DateTime) {
        selectedDate = widget.initialValue;
      } else if (widget.initialValue is String) {
        selectedDate = DateTime.tryParse(widget.initialValue);
      }
    }
    
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
          locale: const Locale('pt', 'BR'),
          helpText: 'Selecionar data',
          cancelText: 'Cancelar',
          confirmText: 'Confirmar',
          errorFormatText: 'Formato inválido',
          errorInvalidText: 'Data inválida',
          fieldLabelText: 'Digite a data',
          fieldHintText: 'dd/mm/aaaa',
        );
        if (date != null) {
          setState(() {
            selectedDate = date;
          });
          widget.onChanged(date);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selectedDate != null
                    ? '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}'
                    : 'Selecione uma data',
                style: TextStyle(
                  fontSize: 16,
                  color: selectedDate != null ? Colors.black : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeInput() {
    DateTime? selectedDateTime;
    
    if (widget.initialValue != null) {
      if (widget.initialValue is DateTime) {
        selectedDateTime = widget.initialValue;
      } else if (widget.initialValue is String) {
        selectedDateTime = DateTime.tryParse(widget.initialValue);
      }
    }
    
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDateTime ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
          locale: const Locale('pt', 'BR'),
          helpText: 'Selecionar data',
          cancelText: 'Cancelar',
          confirmText: 'Confirmar',
          errorFormatText: 'Formato inválido',
          errorInvalidText: 'Data inválida',
          fieldLabelText: 'Digite a data',
          fieldHintText: 'dd/mm/aaaa',
        );
        
        if (date != null) {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(selectedDateTime ?? DateTime.now()),
            helpText: 'Selecionar horário',
            cancelText: 'Cancelar',
            confirmText: 'Confirmar',
            errorInvalidText: 'Horário inválido',
            hourLabelText: 'Hora',
            minuteLabelText: 'Minuto',
          );
          
          if (time != null) {
            final dateTime = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
            setState(() {
              selectedDateTime = dateTime;
            });
            widget.onChanged(dateTime);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selectedDateTime != null
                    ? '${selectedDateTime.day.toString().padLeft(2, '0')}/${selectedDateTime.month.toString().padLeft(2, '0')}/${selectedDateTime.year} ${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}'
                    : 'Selecione data e hora',
                style: TextStyle(
                  fontSize: 16,
                  color: selectedDateTime != null ? Colors.black : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioOptions() {
    print('🔘 Building radio options');
    print('📋 Options available: ${widget.question.options.length}');
    
    if (widget.question.options.isEmpty) {
      print('⚠️ No options available for radio question');
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
            const SizedBox(height: 10),
            const Text(
              'Nenhuma opção disponível para esta questão',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              'Tipo: ${widget.question.questionType}',
              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
            ),
          ],
        ),
      );
    }

    print('📋 Current selected radio value: $_selectedRadioValue');
    
    return Column(
      children: widget.question.options.asMap().entries.map((entry) {
        final int index = entry.key;
        final option = entry.value;
        final valueToUse = option.optionValue ?? option.optionText;
        final isSelected = _selectedRadioValue == valueToUse;
        
        print('🔘 Option $index: text="${option.optionText}", value="$valueToUse", selected=$isSelected');
        
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () {
              print('🔘 Radio option tapped: ${option.optionText} (value: $valueToUse)');
              setState(() {
                _selectedRadioValue = valueToUse;
              });
              print('📋 New selected radio value: $_selectedRadioValue');
              widget.onChanged(valueToUse);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF8FAF6) : Colors.white,
                border: Border.all(
                  color: isSelected ? const Color(0xFF8FAE5D) : Colors.grey.shade300,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Radio<String>(
                    value: valueToUse,
                    groupValue: _selectedRadioValue,
                    onChanged: (value) {
                      print('🔘 Radio changed via widget: $value');
                      setState(() {
                        _selectedRadioValue = value;
                      });
                      print('📋 New selected radio value: $_selectedRadioValue');
                      widget.onChanged(value);
                    },
                    activeColor: const Color(0xFF8FAE5D),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.optionText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCheckboxOptions() {
    print('☑️ Building checkbox options');
    print('📋 Options available: ${widget.question.options.length}');
    
    if (widget.question.options.isEmpty) {
      print('⚠️ No options available for checkbox question');
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
            const SizedBox(height: 10),
            const Text(
              'Nenhuma opção disponível para esta questão',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              'Tipo: ${widget.question.questionType}',
              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
            ),
          ],
        ),
      );
    }
    
    print('📋 Current selected checkbox values: $_selectedCheckboxValues');
    
    return Column(
      children: widget.question.options.asMap().entries.map((entry) {
        final int index = entry.key;
        final option = entry.value;
        final valueToUse = option.optionValue ?? option.optionText;
        final isSelected = _selectedCheckboxValues.contains(valueToUse);
        
        print('☑️ Option $index: text="${option.optionText}", value="$valueToUse", selected=$isSelected');
        
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () {
              print('☑️ Checkbox option tapped: ${option.optionText} (value: $valueToUse)');
              setState(() {
                if (isSelected) {
                  _selectedCheckboxValues.remove(valueToUse);
                  print('❌ Removed: $valueToUse');
                } else {
                  _selectedCheckboxValues.add(valueToUse);
                  print('✅ Added: $valueToUse');
                }
              });
              print('📋 New selected checkbox values: $_selectedCheckboxValues');
              widget.onChanged(List<String>.from(_selectedCheckboxValues));
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF8FAF6) : Colors.white,
                border: Border.all(
                  color: isSelected ? const Color(0xFF8FAE5D) : Colors.grey.shade300,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      print('☑️ Checkbox changed via widget: $value');
                      setState(() {
                        if (value == true) {
                          _selectedCheckboxValues.add(valueToUse);
                          print('✅ Added via checkbox: $valueToUse');
                        } else {
                          _selectedCheckboxValues.remove(valueToUse);
                          print('❌ Removed via checkbox: $valueToUse');
                        }
                      });
                      print('📋 New selected checkbox values: $_selectedCheckboxValues');
                      widget.onChanged(List<String>.from(_selectedCheckboxValues));
                    },
                    activeColor: const Color(0xFF8FAE5D),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.optionText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}