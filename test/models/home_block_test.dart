import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/home_block.dart';

void main() {
  group('parse — defaults', () {
    test('null is the untouched default', () {
      final layout = HomeLayoutCodec.parse(null);
      expect(layout.order, HomeBlock.values);
      expect(layout.hidden, isEmpty);
      expect(layout.isDefault, isTrue);
    });

    test('an unparseable value falls back rather than blanking the screen', () {
      final layout = HomeLayoutCodec.parse('v2:nope,alsoNope');
      expect(layout.visible, HomeBlock.values);
    });
  });

  group('parse — v2 format', () {
    test('reads order and hidden flags', () {
      final layout = HomeLayoutCodec.parse(
          'v2:recent,-welcome,workout,quickActions,heatmap');
      expect(layout.order, [
        HomeBlock.recent,
        HomeBlock.welcome,
        HomeBlock.workout,
        HomeBlock.quickActions,
        HomeBlock.heatmap,
        // Added after this value was written, so appended visible.
        HomeBlock.weightGoal,
      ]);
      expect(layout.hidden, {HomeBlock.welcome});
      expect(layout.visible, [
        HomeBlock.recent,
        HomeBlock.workout,
        HomeBlock.quickActions,
        HomeBlock.heatmap,
        HomeBlock.weightGoal,
      ]);
    });

    test('a block missing from a v2 value arrives visible', () {
      // How a section added in a later version reaches someone who has
      // already customised their home screen.
      final layout = HomeLayoutCodec.parse('v2:recent,-welcome');
      expect(layout.order.length, HomeBlock.values.length);
      expect(layout.isVisible(HomeBlock.heatmap), isTrue);
      expect(layout.hidden, {HomeBlock.welcome});
    });

    test('tolerates whitespace, duplicates and unknown keys', () {
      final layout =
          HomeLayoutCodec.parse('v2: recent , recent , -ghost , workout ');
      expect(layout.order.take(2), [HomeBlock.recent, HomeBlock.workout]);
      expect(layout.hidden, isEmpty);
    });

    test('every block hidden is representable', () {
      final all = HomeLayout(
          order: HomeBlock.values, hidden: HomeBlock.values.toSet());
      final layout = HomeLayoutCodec.parse(all.encode());
      expect(layout.visible, isEmpty);
    });
  });

  group('parse — legacy format', () {
    test('listed keys are visible in order, unlisted are hidden', () {
      // The first shipped format stored only visible keys.
      final layout = HomeLayoutCodec.parse('recent,workout');
      expect(layout.visible, [HomeBlock.recent, HomeBlock.workout]);
      expect(layout.isVisible(HomeBlock.heatmap), isFalse);
      expect(layout.isVisible(HomeBlock.welcome), isFalse);
    });

    test('an empty string still means "everything hidden"', () {
      expect(HomeLayoutCodec.parse('').visible, isEmpty);
      expect(HomeLayoutCodec.parse('   ').visible, isEmpty);
    });

    test('a legacy value keeps its order after re-encoding', () {
      final legacy = HomeLayoutCodec.parse('recent,workout');
      final reparsed = HomeLayoutCodec.parse(legacy.encode());
      expect(reparsed.visible, legacy.visible);
      expect(reparsed.hidden, legacy.hidden);
    });
  });

  group('encode', () {
    test('the untouched default encodes as null', () {
      expect(HomeLayout.defaultLayout.encode(), isNull);
    });

    test('a customised layout carries the version prefix', () {
      final layout =
          HomeLayout.defaultLayout.withVisibility(HomeBlock.welcome, false);
      expect(layout.encode(), startsWith('v2:'));
      expect(layout.encode(), contains('-welcome'));
    });

    test('lists every block, hidden included', () {
      final encoded =
          HomeLayout.defaultLayout.withVisibility(HomeBlock.recent, false)
              .encode()!;
      for (final block in HomeBlock.values) {
        expect(encoded, contains(block.key));
      }
    });
  });

  group('withVisibility', () {
    test('hiding a block leaves the order untouched', () {
      final reordered = HomeLayout.defaultLayout.reordered(4, 0);
      final hidden = reordered.withVisibility(HomeBlock.workout, false);
      expect(hidden.order, reordered.order);
    });

    test('switching back on restores the original position', () {
      // The bug this model replaces: re-enabling a block rebuilt the visible
      // list from the default order, scrambling everything else.
      final custom = HomeLayout.defaultLayout.reordered(4, 0);
      final orderBefore = List.of(custom.order);

      final toggledOff = custom.withVisibility(HomeBlock.quickActions, false);
      final toggledOn = toggledOff.withVisibility(HomeBlock.quickActions, true);

      expect(toggledOn.order, orderBefore);
      expect(toggledOn.visible, custom.visible);
      expect(toggledOn.hidden, isEmpty);
    });

    test('survives a save/load round trip', () {
      final custom = HomeLayout.defaultLayout
          .reordered(3, 0)
          .withVisibility(HomeBlock.welcome, false);
      final reloaded = HomeLayoutCodec.parse(custom.encode());
      expect(reloaded.order, custom.order);
      expect(reloaded.hidden, custom.hidden);
    });
  });

  group('reordered', () {
    test('moving down accounts for the removal offset', () {
      final moved = HomeLayout.defaultLayout.reordered(0, 3);
      expect(moved.order[2], HomeBlock.values.first);
    });

    test('moving up places the block at the target index', () {
      final moved = HomeLayout.defaultLayout.reordered(3, 0);
      expect(moved.order.first, HomeBlock.values[3]);
    });

    test('reordering never changes which blocks are hidden', () {
      final hidden =
          HomeLayout.defaultLayout.withVisibility(HomeBlock.heatmap, false);
      expect(hidden.reordered(0, 4).hidden, hidden.hidden);
    });
  });

  test('every block has a unique, stable key', () {
    final keys = HomeBlock.values.map((b) => b.key).toSet();
    expect(keys.length, HomeBlock.values.length);
    for (final block in HomeBlock.values) {
      expect(HomeBlock.fromKey(block.key), block);
    }
  });
}
