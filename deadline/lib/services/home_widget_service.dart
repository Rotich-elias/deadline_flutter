import 'package:home_widget/home_widget.dart';

import '../models/task.dart';
import '../utils/urgency.dart';

const _androidWidgetName = 'DeadlineWidgetProvider';

/// Pushes the next open deadline and overdue count to the Android home
/// screen widget. Fire-and-forget: a widget-less phone just ignores this.
class HomeWidgetService {
  static Future<void> update(List<Task> tasks) async {
    final open = tasks.where((t) => !t.done).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final overdueCount = open.where((t) => t.isOverdue).length;

    if (open.isEmpty) {
      await HomeWidget.saveWidgetData<String>('title', 'Nothing due');
      await HomeWidget.saveWidgetData<String>('countdown', '');
      await HomeWidget.saveWidgetData<String>('overdue', '');
    } else {
      final next = open.first;
      await HomeWidget.saveWidgetData<String>('title', next.title);
      await HomeWidget.saveWidgetData<String>(
          'countdown', countdownOf(next));
      await HomeWidget.saveWidgetData<String>(
          'overdue', overdueCount > 0 ? '$overdueCount overdue' : '');
    }

    await HomeWidget.updateWidget(androidName: _androidWidgetName);
  }
}
