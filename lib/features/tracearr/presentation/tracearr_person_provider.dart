import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// How many pages of people are read to find one by name. A live stream names
/// its viewer by name and carries no id, so Live finds the person among the
/// people Tracearr lists; a household has a handful and a big server a few
/// hundred, and past this many pages we say we do not know rather than keep
/// asking.
const int kTracearrDirectoryPages = 5;

/// How many recent viewings a person's page lists.
const int kTracearrPersonHistory = 10;

/// The people Tracearr lists, a few pages of them, for what needs to choose
/// one or find one by name (History's person filter, Live's door to a person).
///
/// A household has a handful and a big server a few hundred; past
/// [kTracearrDirectoryPages] pages we stop asking and work with what we have.
/// People whose every account was removed are not listed, as on the Users tab.
final tracearrPeopleProvider = FutureProvider<List<TracearrUser>>((ref) async {
  final client = ref.watch(tracearrClientProvider);
  final people = <TracearrUser>[];
  String? cursor;
  for (var page = 0; page < kTracearrDirectoryPages; page++) {
    final read = await client.getUsers(
      cursor: cursor,
      pageSize: kTracearrMaxPageSize,
    );
    people.addAll(read.items);
    cursor = read.nextCursor;
    if (cursor == null) break;
  }
  return List.unmodifiable(people);
}, retry: noProviderRetry);

/// The name a person is listed under: the one the owner gave them, else their
/// Tracearr name.
String tracearrPersonName(TracearrUser user) {
  final name = user.displayName.trim();
  return name.isEmpty ? 'Unnamed user' : name;
}

/// People by the names a stream can call them, for a live row that carries no
/// user id: each name (lowercased) to the id of the one person who has it, or
/// to null when two people do (a name that does not say who is not a door).
///
/// A name is a person's Tracearr name, the name the owner gave them, or the
/// name of any account of theirs on a server.
final tracearrPersonDirectoryProvider = FutureProvider<Map<String, String?>>((
  ref,
) async {
  final people = await ref.watch(tracearrPeopleProvider.future);
  final directory = <String, String?>{};
  void add(String? name, String id) {
    final key = name?.trim().toLowerCase() ?? '';
    if (key.isEmpty) return;
    directory[key] = directory.containsKey(key) && directory[key] != id
        ? null
        : id;
  }

  for (final user in people) {
    // Each person counts once per name, so a person who goes by the same
    // name everywhere is not ambiguous with themselves.
    final names = {
      user.username,
      user.identityName,
      for (final account in user.activeAccounts) account.username,
    };
    for (final name in names) {
      add(name, user.id);
    }
  }
  return directory;
}, retry: noProviderRetry);

/// The Tracearr id of the person a row is about: the row's own when it carries
/// one (history and violations do), else the one person the directory knows by
/// that name. Null when nobody, or more than one, does.
final tracearrPersonIdProvider =
    FutureProvider.family<String?, ({String? id, String name})>((
      ref,
      who,
    ) async {
      final id = who.id;
      if (id != null) return id;
      final directory = await ref.watch(tracearrPersonDirectoryProvider.future);
      return directory[who.name.trim().toLowerCase()];
    }, retry: noProviderRetry);

/// A person, or null when Tracearr does not know the id.
final tracearrPersonProvider = FutureProvider.family<TracearrUser?, String>(
  (ref, id) => ref.watch(tracearrClientProvider).getUser(id),
  retry: noProviderRetry,
);

/// A person's figures for 7 and 30 days and all time, with their favourite
/// genres, or null when Tracearr does not know the id.
final tracearrPersonStatsProvider =
    FutureProvider.family<TracearrUserStats?, String>(
      (ref, id) => ref.watch(tracearrClientProvider).getUserStats(id),
      retry: noProviderRetry,
    );

/// A person's most recent viewings, newest first.
final tracearrPersonHistoryProvider =
    FutureProvider.family<TracearrPage<TracearrHistoryEntry>, String>(
      (ref, id) => ref
          .watch(tracearrClientProvider)
          .getHistory(
            pageSize: kTracearrPersonHistory,
            filter: TracearrHistoryFilter(userId: id),
          ),
      retry: noProviderRetry,
    );
