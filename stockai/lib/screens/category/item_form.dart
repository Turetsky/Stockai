part of '../category_screen.dart';

// ─────────────────────────────────────────────────────────────
//  Item Form  (add / edit item)
// ─────────────────────────────────────────────────────────────

class _ItemForm extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic>? existing;
  final bool isEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final VoidCallback? onManageFields;

  const _ItemForm({
    required this.fields,
    required this.existing,
    required this.isEdit,
    required this.onSave,
    this.onManageFields,
  });

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final f in widget.fields)
        f['field_name'] as String: TextEditingController(
          text: widget.existing?[f['field_name']]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!mounted) return;
    // Validate mandatory anchor fields
    if (widget.fields.isNotEmpty) {
      final nameVal = _controllers[widget.fields[0]['field_name']]?.text.trim() ?? '';
      if (nameVal.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name is required.')),
        );
        return;
      }
    }
    if (widget.fields.length > 1) {
      final qtyVal = _controllers[widget.fields[1]['field_name']]?.text.trim() ?? '';
      if (qtyVal.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantity is required.')),
        );
        return;
      }
    }
    // Validate numeric fields before hitting the DB
    for (final f in widget.fields) {
      final ft = f['field_type'] as String? ?? 'text';
      if (ft == 'number' || ft == 'integer' || ft == 'float') {
        final val = _controllers[f['field_name']]?.text.trim() ?? '';
        if (val.isNotEmpty && num.tryParse(val) == null) {
          final dn = f['display_name'] as String? ?? f['field_name'] as String;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$dn" must be a number.')),
          );
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        for (final f in widget.fields)
          f['field_name'] as String: () {
            final val = _controllers[f['field_name']]?.text.trim() ?? '';
            final ft = f['field_type'] as String? ?? 'text';
            if (val.isEmpty && (ft == 'number' || ft == 'integer' || ft == 'float')) {
              return null;
            }
            return val.isEmpty ? null : val;
          }(),
      };
      await widget.onSave(data);
      if (mounted) Navigator.pop(context);
      // Widget is now closing — don't setState again
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.isEdit ? 'Edit Item' : 'Add Item',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (widget.onManageFields != null)
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: 'Manage Fields',
                  onPressed: widget.onManageFields,
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...widget.fields.asMap().entries.map((entry) {
            final idx = entry.key;
            final f = entry.value;
            final fieldName = f['field_name'] as String;
            final displayName = f['display_name'] as String? ?? fieldName;
            final fieldType = f['field_type'] as String? ?? 'text';
            final isRequired = idx == 0 || idx == 1;
            final label = isRequired ? '$displayName *' : displayName;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controllers[fieldName],
                keyboardType: TextInputType.text,
                maxLines: fieldType == 'textarea' ? 3 : 1,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.isEdit ? 'Save Changes' : 'Add Item'),
          ),
        ],
      ),
    ),
    );
  }
}
