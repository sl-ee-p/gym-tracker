/// The dashboard's sections, in their default order.
enum HomeBlock {
  workout('workout', 'Start / resume workout'),
  welcome('welcome', 'Welcome card'),
  quickActions('quickActions', 'Quick actions'),
  heatmap('heatmap', 'Consistency & achievements'),
  recent('recent', 'Recent workouts'),
  weightGoal('weightGoal', 'Weight goal');

  const HomeBlock(this.key, this.label);

  /// Stable identifier written to the database. Never rename one of these
  /// without a migration — a renamed key reads as an unknown block.
  final String key;

  /// Human-readable name, shown on the customise screen.
  final String label;

  static HomeBlock? fromKey(String key) {
    for (final block in HomeBlock.values) {
      if (block.key == key) return block;
    }
    return null;
  }
}

/// The dashboard's block order together with which of them are hidden.
///
/// Order and visibility are stored together, for every block, so hiding one
/// doesn't lose where it sat. The first version stored only the visible keys,
/// which meant switching a block back on had nowhere to put it but the default
/// position — and re-deriving the list from the default order scrambled
/// everything else along with it.
class HomeLayout {
  const HomeLayout({required this.order, required this.hidden});

  /// Every known block, in display order.
  final List<HomeBlock> order;

  /// Which of [order] are hidden from the dashboard.
  final Set<HomeBlock> hidden;

  static const defaultLayout =
      HomeLayout(order: HomeBlock.values, hidden: <HomeBlock>{});

  /// Blocks the dashboard actually renders, in order.
  List<HomeBlock> get visible =>
      [for (final block in order) if (!hidden.contains(block)) block];

  bool isVisible(HomeBlock block) => !hidden.contains(block);

  bool get isDefault =>
      hidden.isEmpty && _sameOrder(order, HomeBlock.values);

  static bool _sameOrder(List<HomeBlock> a, List<HomeBlock> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  HomeLayout withVisibility(HomeBlock block, bool visible) {
    final next = Set<HomeBlock>.from(hidden);
    if (visible) {
      next.remove(block);
    } else {
      next.add(block);
    }
    // `order` is untouched: a block keeps its position whether or not it is
    // shown, so toggling it off and back on puts it back exactly where it was.
    return HomeLayout(order: order, hidden: next);
  }

  HomeLayout reordered(int oldIndex, int newIndex) {
    final next = List<HomeBlock>.from(order);
    // ReorderableListView reports newIndex as the slot before removal.
    if (newIndex > oldIndex) newIndex -= 1;
    next.insert(newIndex, next.removeAt(oldIndex));
    return HomeLayout(order: next, hidden: hidden);
  }
}

/// Serialisation for `user_profiles.homeLayout`.
///
/// Two formats exist on disk. The current one is prefixed `v2:` and lists
/// *every* block in order, hidden ones marked with a leading `-`:
///
///     v2:workout,-welcome,heatmap,quickActions,recent
///
/// The first shipped version listed only the visible keys, with hidden ones
/// simply absent. Both are read; only `v2:` is written. The prefix is what
/// makes them distinguishable — without it, a layout with nothing hidden is
/// indistinguishable from an old one, and a block added in a later version
/// would be silently hidden for everyone who had ever customised their home
/// screen.
extension HomeLayoutCodec on HomeLayout {
  static const _version = 'v2:';
  static const _hiddenPrefix = '-';

  /// Parses a stored value. Tolerant by design: unknown keys are dropped, and
  /// any block the stored value doesn't mention is appended, visible, in its
  /// default position relative to the others — that is how a block introduced
  /// in a later version reaches an existing user.
  static HomeLayout parse(String? stored) {
    if (stored == null) return HomeLayout.defaultLayout;

    final trimmed = stored.trim();
    if (trimmed.isEmpty) {
      // Legacy "everything hidden". Kept working rather than reset, since it
      // was a deliberate choice at the time.
      return HomeLayout(
        order: HomeBlock.values,
        hidden: HomeBlock.values.toSet(),
      );
    }

    final isV2 = trimmed.startsWith(_version);
    final body = isV2 ? trimmed.substring(_version.length) : trimmed;

    final order = <HomeBlock>[];
    final hidden = <HomeBlock>{};
    for (final rawEntry in body.split(',')) {
      var entry = rawEntry.trim();
      if (entry.isEmpty) continue;
      final isHidden = entry.startsWith(_hiddenPrefix);
      if (isHidden) entry = entry.substring(_hiddenPrefix.length).trim();

      final block = HomeBlock.fromKey(entry);
      if (block == null || order.contains(block)) continue;
      order.add(block);
      if (isHidden) hidden.add(block);
    }

    if (order.isEmpty) return HomeLayout.defaultLayout;

    for (final block in HomeBlock.values) {
      if (order.contains(block)) continue;
      order.add(block);
      // In the legacy format, absence meant hidden. In v2 every known block is
      // written, so absence means "added after this layout was saved" — and a
      // new block should show up rather than arrive invisible.
      if (!isV2) hidden.add(block);
    }

    return HomeLayout(order: order, hidden: hidden);
  }

  /// Encodes for storage, or null when the layout is the untouched default —
  /// so "never customised" keeps inheriting whatever the defaults become.
  String? encode() {
    if (isDefault) return null;
    final entries = [
      for (final block in order)
        '${hidden.contains(block) ? _hiddenPrefix : ''}${block.key}',
    ];
    return '$_version${entries.join(',')}';
  }
}
