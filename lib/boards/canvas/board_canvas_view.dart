import 'package:flutter/material.dart';

import '../boards_controller.dart';
import '../boards_repository.dart';

/// The infinite canvas of a board (docs/boards/DESIGN.md §8).
///
/// STUB: the canvas implementation replaces this body; the constructor is
/// the contract the board page uses.
class BoardCanvasView extends StatefulWidget {
  const BoardCanvasView({
    super.key,
    required this.board,
    required this.viewState,
    required this.onViewChanged,
    required this.onOpenCard,
    required this.stylusOnly,
    this.onStylusDetected,
  });

  final OpenBoard board;

  /// This device's last viewport for the board, if any.
  final BoardViewState? viewState;

  /// Called (throttled) when the viewport settles; the page saves it.
  final ValueChanged<BoardViewState> onViewChanged;

  /// A card was double-tapped: open the card sheet.
  final void Function(String cardId) onOpenCard;

  /// Palm rejection: only the stylus draws.
  final bool stylusOnly;

  /// First stylus contact (turns stylusOnly on when the setting allows).
  final VoidCallback? onStylusDetected;

  @override
  State<BoardCanvasView> createState() => _BoardCanvasViewState();
}

class _BoardCanvasViewState extends State<BoardCanvasView> {
  @override
  Widget build(BuildContext context) => const Center(child: Text('Tuval'));
}
