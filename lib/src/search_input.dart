import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_map_location_picker/generated/l10n.dart';

/// Custom Search input field, showing the search and clear icons.
class SearchInput extends StatefulWidget {
  SearchInput(
    this.onSearchInput, {
    Key key,
    this.searchInputKey,
    this.boxDecoration,
    this.hintText,
  }) : super(key: key);

  final ValueChanged<String> onSearchInput;
  final Key searchInputKey;
  final BoxDecoration boxDecoration;
  final String hintText;

  @override
  State<StatefulWidget> createState() => SearchInputState();
}

class SearchInputState extends State<SearchInput> {
  TextEditingController editController = TextEditingController();

  Timer debouncer;

  bool hasSearchEntry = false;

  @override
  void initState() {
    super.initState();
    editController.addListener(onSearchInputChange);
  }

  @override
  void dispose() {
    editController.removeListener(onSearchInputChange);
    editController.dispose();

    super.dispose();
  }

  void onSearchInputChange() {
    if (editController.text.isEmpty) {
      debouncer?.cancel();
      widget.onSearchInput(editController.text);
      return;
    }

    if (debouncer?.isActive ?? false) {
      debouncer.cancel();
    }

    debouncer = Timer(Duration(milliseconds: 500), () {
      widget.onSearchInput(editController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.boxDecoration ??
          BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Color(0xFFB3B2B2),
          ),
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: editController,
              decoration: InputDecoration(
                hintText: widget.hintText ?? S.of(context)?.search_place ?? 'Search place',
                border: InputBorder.none,
                hintStyle: TextStyle(
                    color: Color(0xFF818181),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Mulish'),
              ),
              style: TextStyle(
                  color: Color(0xFF818181),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Mulish'),
              onChanged: (value) {
                setState(() {
                  hasSearchEntry = value.isNotEmpty;
                });
              },
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            child: Container(
              decoration: BoxDecoration(
                color: Color(0xFF818181),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.clear_sharp,
                  color: Colors.white,
                ),
              ),
            ),
            onTap: () {
              editController.clear();
              setState(() {
                hasSearchEntry = false;
              });
            },
          )
        ],
      ),
    );
  }
}
