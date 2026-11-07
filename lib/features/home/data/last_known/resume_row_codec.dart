/// A title somebody started and did not finish, as a last drawing keeps it:
/// the item (`stream_item_codec.dart`) and the connection it is on.
///
/// What Continue watching draws, and what Featured's resume slide and its
/// Play are made of. The connection is its id and its display name (the
/// label the person gave it), which are what the row opens and says; the
/// pictures are built from the item's paths through that connection's client
/// when they are drawn.
library;

import 'package:cupola/features/home/data/last_known/stored_fields.dart';
import 'package:cupola/features/home/data/last_known/stream_item_codec.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

Map<String, Object?> resumeRowToJson(ResumeRow row) => {
  'service': row.service.name,
  'instanceId': row.instanceId,
  'connectionName': ?row.connectionName,
  'item': streamItemToJson(row.item),
};

/// [json] read back; null for a row this version cannot read whole, and for
/// one on a service that is no media server.
ResumeRow? resumeRowFromJson(Object? json) {
  final fields = StoredFields(json);
  final service = fields.service('service', required: true);
  final instanceId = fields.text('instanceId', required: true);
  final connectionName = fields.text('connectionName');
  final item = streamItemFromJson(fields.raw('item'));
  if (fields.isBroken || item == null || instanceId == null) return null;
  if (service == null || !service.isMediaServer) return null;
  return (
    service: service,
    instanceId: instanceId,
    connectionName: connectionName,
    item: item,
  );
}
