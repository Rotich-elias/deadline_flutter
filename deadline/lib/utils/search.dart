/// Case-insensitive substring search shared by the deadlines and notes lists.
///
/// [fields] pulls the searchable text out of one item. A whitespace-only query
/// matches everything, so the callers can filter unconditionally.
List<T> filterByQuery<T>(
  Iterable<T> items,
  String query,
  Iterable<String?> Function(T item) fields,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return List<T>.from(items);

  return [
    for (final item in items)
      if (fields(item).any(
          (field) => field != null && field.toLowerCase().contains(needle)))
        item,
  ];
}
