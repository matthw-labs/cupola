import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
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
///
/// Dropped when nothing is watching it, which is the point: a read that failed
/// once, or a list that has since gained a person in Tracearr, is read again
/// the next time something asks, instead of being kept for the whole session.
final tracearrPeopleProvider = FutureProvider.autoDispose<List<TracearrUser>>((
  ref,
) async {
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
///
/// Dropped with [tracearrPeopleProvider] it is read from, for the same reason.
final tracearrPersonDirectoryProvider =
    FutureProvider.autoDispose<Map<String, String?>>((ref) async {
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
///
/// Dropped when the sheet that asks for it closes, with the directory under it.
final tracearrPersonIdProvider = FutureProvider.autoDispose
    .family<String?, ({String? id, String name})>((ref, who) async {
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

/// The kind of server in Tracearr's words for a media server of ours, or null
/// for a service that is not one Tracearr watches.
TracearrServerType? tracearrServerTypeOf(ServiceKey service) =>
    switch (service) {
      ServiceKey.plex => TracearrServerType.plex,
      ServiceKey.jellyfin => TracearrServerType.jellyfin,
      ServiceKey.emby => TracearrServerType.emby,
      _ => null,
    };

/// A person's account on a media server, as a list of users there names it:
/// [serverUserId] is the id of the user on the server itself (the `Id` of a
/// Jellyfin or Emby user, the account id of a Plex one), and [serverName] the
/// name of the server when it is known, which tells two servers of one kind
/// apart.
typedef TracearrAccountKey = ({
  ServiceKey service,
  String serverUserId,
  String? serverName,
});

/// The Tracearr person who holds the account [key] names, or null when
/// Tracearr has none, or more than one (an id that does not say who is not a
/// door).
///
/// Matched on `accounts.external_user_id` against the id of the user on the
/// server, among accounts still on a server and of the same kind of server.
/// An id shared by accounts on two servers of that kind (a Plex account is
/// one id everywhere) is narrowed by the server's name, when it is given and
/// Tracearr has a server of that name; else it is ambiguous and null.
///
/// Reads the connection in view, whose person page the door opens.
final tracearrPersonByAccountProvider = FutureProvider.autoDispose
    .family<String?, TracearrAccountKey>((ref, key) async {
      final type = tracearrServerTypeOf(key.service);
      if (type == null || key.serverUserId.trim().isEmpty) return null;
      final people = await ref.watch(tracearrPeopleProvider.future);
      final holders = <(String person, String server)>{
        for (final user in people)
          for (final account in user.activeAccounts)
            if (account.serverType == type &&
                account.externalUserId == key.serverUserId)
              (user.id, account.serverId),
      };
      final persons = {for (final (person, _) in holders) person};
      if (persons.length <= 1) return persons.firstOrNull;
      final name = key.serverName?.trim().toLowerCase() ?? '';
      if (name.isEmpty) return null;
      final servers = await ref.watch(tracearrServersProvider.future);
      final ids = {
        for (final server in servers.servers)
          if (server.name.trim().toLowerCase() == name) server.id,
      };
      final narrowed = {
        for (final (person, server) in holders)
          if (ids.contains(server)) person,
      };
      return narrowed.length == 1 ? narrowed.single : null;
    }, retry: noProviderRetry);

/// Who a session row is about, for the door to their Tracearr page.
typedef TracearrSessionWho = ({
  ServiceKey service,
  String? userId,
  String name,
});

/// The Tracearr person a session's viewer is: by their account on that server
/// when the session carries the id of the user
/// ([tracearrPersonByAccountProvider]), and only for a session that carries
/// none, by the one person Tracearr knows by that name
/// ([tracearrPersonIdProvider]). Null when neither says who, which is when no
/// door is drawn: only a known person has a page to lead to.
///
/// **An id that did not resolve is not a reason to try the name.** It says
/// either that Tracearr holds no such account or that the account is on two
/// of its servers and cannot be told apart, and a name is the weaker
/// evidence: it would open whichever single person happens to go by it on
/// any server, which can be somebody else.
final tracearrPersonOfSessionProvider = FutureProvider.autoDispose
    .family<String?, TracearrSessionWho>((ref, who) async {
      final id = who.userId;
      if (id != null && id.trim().isNotEmpty) {
        return ref.watch(
          tracearrPersonByAccountProvider((
            service: who.service,
            serverUserId: id,
            serverName: null,
          )).future,
        );
      }
      if (who.name.trim().isEmpty) return null;
      return ref.watch(
        tracearrPersonIdProvider((id: null, name: who.name)).future,
      );
    }, retry: noProviderRetry);
