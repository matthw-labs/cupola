import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';

/// Who is watching, as a stream, a history row or a violation names them.
///
/// A person's name, avatar and ids are theirs: [toString] prints none of it,
/// so a log line or a failure message that formats a row cannot leak them.
final class TracearrPerson {
  const TracearrPerson({
    this.id,
    this.serverUserId,
    this.name = '',
    this.avatarUrl,
    this.thumbUrl,
  });

  /// A person from the flat fields of a live stream: `username`, `user_thumb`
  /// and `user_avatar_url`. A live row carries no user id.
  factory TracearrPerson.fromStreamRow(TracearrJson json) => TracearrPerson(
    name: json.text('username') ?? '',
    thumbUrl: json.text('user_thumb'),
    avatarUrl: json.text('user_avatar_url'),
  );

  /// A person from a nested `user` object (history and violations).
  factory TracearrPerson.fromJson(TracearrJson json) => TracearrPerson(
    id: json.text('id'),
    serverUserId: json.text('server_user_id'),
    name: json.text('username') ?? '',
    thumbUrl: json.text('thumb_url'),
    avatarUrl: json.text('avatar_url'),
  );

  /// The Tracearr user: one person across servers. Null on a live stream.
  final String? id;

  /// The account on that one server.
  final String? serverUserId;

  final String name;

  /// A path on Tracearr, relative; see `resolveTracearrImage`. Prefer it over
  /// [thumbUrl], which is the media server's own.
  final String? avatarUrl;

  final String? thumbUrl;

  @override
  String toString() => 'TracearrPerson()';
}

/// The ids a title is known by, outside and inside Tracearr.
final class TracearrMediaIds {
  const TracearrMediaIds({
    this.mediaId,
    this.showMediaId,
    this.tmdb,
    this.tvdb,
    this.imdb,
    this.ratingKey,
    this.parentRatingKey,
    this.grandparentRatingKey,
    this.libraryId,
  });

  factory TracearrMediaIds.fromJson(TracearrJson json) => TracearrMediaIds(
    mediaId: json.text('media_id'),
    showMediaId: json.text('show_media_id'),
    tmdb: json.integer('tmdb_id'),
    tvdb: json.integer('tvdb_id'),
    imdb: json.text('imdb_id'),
    ratingKey: json.text('rating_key'),
    parentRatingKey: json.text('parent_rating_key'),
    grandparentRatingKey: json.text('grandparent_rating_key'),
    libraryId: json.text('library_id'),
  );

  /// Tracearr's own id of the title, across servers.
  final String? mediaId;

  /// For an episode, Tracearr's id of its show.
  final String? showMediaId;

  final int? tmdb;
  final int? tvdb;
  final String? imdb;

  /// The media server's own id of the item: what we match on to say two
  /// sources describe the same session.
  final String? ratingKey;
  final String? parentRatingKey;
  final String? grandparentRatingKey;
  final String? libraryId;

  /// Whether any external id (TMDB, TVDB, IMDb) is there to open the title by.
  bool get hasExternalId => tmdb != null || tvdb != null || imdb != null;
}

/// What `GET media/{ref}` says of a title, as far as opening it goes: its kind
/// and the external ids it is known by. Tracearr's own reply holds a good deal
/// more (availability per server, merged ids); none of it is read.
final class TracearrMediaIdentity {
  const TracearrMediaIdentity({
    this.type = TracearrMediaType.unknown,
    this.tmdb,
    this.tvdb,
  });

  factory TracearrMediaIdentity.fromJson(TracearrJson json) =>
      TracearrMediaIdentity(
        type: TracearrMediaType.fromWire(json['media_type']),
        tmdb: json.integer('tmdb_id'),
        tvdb: json.integer('tvdb_id'),
      );

  final TracearrMediaType type;
  final int? tmdb;
  final int? tvdb;
}

/// What is being played.
final class TracearrMedia {
  const TracearrMedia({
    this.type = TracearrMediaType.unknown,
    this.title = '',
    this.showTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.artist,
    this.album,
    this.trackNumber,
    this.discNumber,
    this.thumbPath,
    this.posterUrl,
    this.durationMs,
    this.genres = const [],
    this.ids = const TracearrMediaIds(),
  });

  factory TracearrMedia.fromJson(TracearrJson json) => TracearrMedia(
    type: TracearrMediaType.fromWire(json['media_type']),
    title: json.text('media_title') ?? '',
    showTitle: json.text('show_title'),
    seasonNumber: json.integer('season_number'),
    episodeNumber: json.integer('episode_number'),
    year: json.integer('year'),
    artist: json.text('artist_name'),
    album: json.text('album_name'),
    trackNumber: json.integer('track_number'),
    discNumber: json.integer('disc_number'),
    thumbPath: json.text('thumb_path'),
    posterUrl: json.text('poster_url'),
    durationMs: json.integer('duration_ms'),
    genres: json.strings('genres'),
    ids: TracearrMediaIds.fromJson(json),
  );

  final TracearrMediaType type;

  /// The episode, movie or track title. Empty when the row did not say.
  final String title;

  final String? showTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? discNumber;

  /// The media server's own path of the artwork. Not fetchable by us: use
  /// [posterUrl].
  final String? thumbPath;

  /// A path on Tracearr's image proxy, relative; see `resolveTracearrImage`.
  final String? posterUrl;

  final int? durationMs;
  final List<String> genres;
  final TracearrMediaIds ids;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);
}

/// The device a stream plays on.
final class TracearrDevice {
  const TracearrDevice({this.device, this.player, this.product, this.platform});

  factory TracearrDevice.fromJson(TracearrJson json) => TracearrDevice(
    device: json.text('device'),
    player: json.text('player'),
    product: json.text('product'),
    platform: json.text('platform'),
  );

  final String? device;
  final String? player;
  final String? product;
  final String? platform;

  /// The first name the row gave, device before player before product.
  String? get name => device ?? player ?? product ?? platform;
}

/// One side of a stream, the file or what the client receives.
///
/// The same shape for both, because the screen puts them next to each other
/// (source against output). The source side fills more of it than the output:
/// Tracearr details the file better than what it sends.
final class TracearrMediaFormat {
  const TracearrMediaFormat({
    this.videoCodec,
    this.audioCodec,
    this.videoCodecDisplay,
    this.audioCodecDisplay,
    this.width,
    this.height,
    this.videoBitrate,
    this.frameRate,
    this.dynamicRange,
    this.profile,
    this.level,
    this.colorSpace,
    this.colorDepth,
    this.aspectRatio,
    this.audioBitrate,
    this.audioChannels,
    this.channelLayout,
    this.audioLanguage,
    this.sampleRate,
  });

  final String? videoCodec;
  final String? audioCodec;

  /// The codec as Tracearr prints it (`H.264`, `EAC3`).
  final String? videoCodecDisplay;
  final String? audioCodecDisplay;

  final int? width;
  final int? height;
  final int? videoBitrate;
  final String? frameRate;

  /// `SDR`, `HDR10`, `Dolby Vision` and the like, as the server names it.
  final String? dynamicRange;

  final String? profile;
  final String? level;
  final String? colorSpace;
  final int? colorDepth;
  final double? aspectRatio;
  final int? audioBitrate;
  final int? audioChannels;
  final String? channelLayout;
  final String? audioLanguage;
  final int? sampleRate;

  /// Whether the picture is high dynamic range: a dynamic range that is named
  /// and is not SDR.
  bool get isHdr {
    final range = dynamicRange?.trim().toLowerCase();
    return range != null && range.isNotEmpty && range != 'sdr';
  }
}

/// How the server handles the container and the hardware it uses.
final class TracearrTranscodeInfo {
  const TracearrTranscodeInfo({
    this.containerDecision,
    this.sourceContainer,
    this.streamContainer,
    this.hwRequested,
    this.hwDecoding,
    this.hwEncoding,
    this.speed,
    this.throttled,
    this.reasons = const [],
  });

  factory TracearrTranscodeInfo.fromJson(TracearrJson json) =>
      TracearrTranscodeInfo(
        containerDecision: TracearrDecision.fromWire(json['containerDecision']),
        sourceContainer: json.text('sourceContainer'),
        streamContainer: json.text('streamContainer'),
        hwRequested: json.flag('hwRequested'),
        hwDecoding: json.text('hwDecoding'),
        hwEncoding: json.text('hwEncoding'),
        speed: json.number('speed'),
        throttled: json.flag('throttled'),
        reasons: json.strings('reasons'),
      );

  final TracearrDecision? containerDecision;
  final String? sourceContainer;
  final String? streamContainer;
  final bool? hwRequested;
  final String? hwDecoding;
  final String? hwEncoding;

  /// Transcode speed as a multiple of real time (`1.4` keeps up).
  final double? speed;

  /// The server slowed the transcode down because it is ahead of the viewer.
  final bool? throttled;

  /// Why the server transcodes, as it words them.
  final List<String> reasons;

  bool get usesHardware => (hwDecoding ?? hwEncoding) != null;
}

final class TracearrSubtitle {
  const TracearrSubtitle({
    this.decision,
    this.codec,
    this.language,
    this.forced,
  });

  factory TracearrSubtitle.fromJson(TracearrJson json) => TracearrSubtitle(
    decision: json.text('decision'),
    codec: json.text('codec'),
    language: json.text('language'),
    forced: json.flag('forced'),
  );

  /// As the server words it (`burn`, `copy`, `none`): the contract does not
  /// fix the set, so we do not pretend to.
  final String? decision;
  final String? codec;
  final String? language;
  final bool? forced;
}

/// How a session reaches the viewer: the verdict, the file and what is sent.
final class TracearrQuality {
  const TracearrQuality({
    this.isTranscode = false,
    this.videoDecision,
    this.audioDecision,
    this.bitrate,
    this.resolution,
    this.audioChannelsDisplay,
    this.source = const TracearrMediaFormat(),
    this.output = const TracearrMediaFormat(),
    this.transcode,
    this.subtitle,
  });

  factory TracearrQuality.fromJson(TracearrJson json) {
    final sourceVideo = json.object('source_video_details');
    final sourceAudio = json.object('source_audio_details');
    final outVideo = json.object('stream_video_details');
    final outAudio = json.object('stream_audio_details');
    final transcode = json.object('transcode_info');
    final subtitle = json.object('subtitle_info');
    return TracearrQuality(
      isTranscode: json.flag('is_transcode') ?? false,
      videoDecision: TracearrDecision.fromWire(json['video_decision']),
      audioDecision: TracearrDecision.fromWire(json['audio_decision']),
      bitrate: json.integer('bitrate'),
      resolution: json.text('resolution'),
      audioChannelsDisplay: json.text('audio_channels_display'),
      source: TracearrMediaFormat(
        videoCodec: json.text('source_video_codec'),
        audioCodec: json.text('source_audio_codec'),
        videoCodecDisplay: json.text('source_video_codec_display'),
        audioCodecDisplay: json.text('source_audio_codec_display'),
        width: json.integer('source_video_width'),
        height: json.integer('source_video_height'),
        videoBitrate: _rounded(sourceVideo, 'bitrate'),
        frameRate: sourceVideo?.text('framerate'),
        dynamicRange: sourceVideo?.text('dynamicRange'),
        profile: sourceVideo?.text('profile'),
        level: sourceVideo?.text('level'),
        colorSpace: sourceVideo?.text('colorSpace'),
        colorDepth: _rounded(sourceVideo, 'colorDepth'),
        aspectRatio: sourceVideo?.number('aspectRatio'),
        audioBitrate: _rounded(sourceAudio, 'bitrate'),
        audioChannels: json.integer('source_audio_channels'),
        channelLayout: sourceAudio?.text('channelLayout'),
        audioLanguage: sourceAudio?.text('language'),
        sampleRate: _rounded(sourceAudio, 'sampleRate'),
      ),
      output: TracearrMediaFormat(
        videoCodec: json.text('stream_video_codec'),
        audioCodec: json.text('stream_audio_codec'),
        videoCodecDisplay: json.text('stream_video_codec_display'),
        audioCodecDisplay: json.text('stream_audio_codec_display'),
        width: _rounded(outVideo, 'width'),
        height: _rounded(outVideo, 'height'),
        videoBitrate: _rounded(outVideo, 'bitrate'),
        frameRate: outVideo?.text('framerate'),
        dynamicRange: outVideo?.text('dynamicRange'),
        audioBitrate: _rounded(outAudio, 'bitrate'),
        audioChannels: _rounded(outAudio, 'channels'),
        audioLanguage: outAudio?.text('language'),
      ),
      transcode: transcode == null
          ? null
          : TracearrTranscodeInfo.fromJson(transcode),
      subtitle: subtitle == null ? null : TracearrSubtitle.fromJson(subtitle),
    );
  }

  static int? _rounded(TracearrJson? json, String key) =>
      json?.number(key)?.round();

  /// The same quality at a new bitrate: the one thing a `stream.progress`
  /// event moves.
  TracearrQuality withBitrate(int? bitrate) => TracearrQuality(
    isTranscode: isTranscode,
    videoDecision: videoDecision,
    audioDecision: audioDecision,
    bitrate: bitrate,
    resolution: resolution,
    audioChannelsDisplay: audioChannelsDisplay,
    source: source,
    output: output,
    transcode: transcode,
    subtitle: subtitle,
  );

  /// Tracearr's own verdict, which can differ from the two decisions below
  /// (a container remux alone is not a transcode).
  final bool isTranscode;

  final TracearrDecision? videoDecision;
  final TracearrDecision? audioDecision;

  /// The stream's bitrate, in the unit Tracearr sends (kilobits per second).
  final int? bitrate;

  /// The size label as Tracearr prints it (`1080p`, `4K`).
  final String? resolution;

  final String? audioChannelsDisplay;
  final TracearrMediaFormat source;
  final TracearrMediaFormat output;
  final TracearrTranscodeInfo? transcode;
  final TracearrSubtitle? subtitle;

  /// Direct play when neither track is converted. A row with no decisions at
  /// all is not claimed as one.
  bool get isDirectPlay =>
      !isTranscode &&
      (videoDecision == TracearrDecision.directPlay ||
          audioDecision == TracearrDecision.directPlay) &&
      videoDecision != TracearrDecision.copy &&
      audioDecision != TracearrDecision.copy;

  /// Direct stream: a track is passed through inside a new container.
  bool get isDirectStream =>
      !isTranscode &&
      (videoDecision == TracearrDecision.copy ||
          audioDecision == TracearrDecision.copy);
}
