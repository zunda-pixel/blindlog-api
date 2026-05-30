import Foundation
import Hummingbird
import PostgresNIO
import Records
import StructuredQueriesPostgres
import UUIDV7

private struct EventSnapshot {
  var event: EventRecord
  var revision: EventRevisionRecord
}

private struct EventQuestionSnapshot {
  var question: EventQuestionRecord
  var revision: EventQuestionRevisionRecord
}

private enum EventRegistrationError: Error {
  case canceledParticipant
}

private enum EventRevisionMutationError: Error {
  case alreadyExists
}

extension API {
  func getEvents(
    _ input: Operations.GetEvents.Input
  ) async throws -> Operations.GetEvents.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    do {
      let events = try await latestEventsVisible(to: userID)
      return .ok(.init(body: .json(events.map(Components.Schemas.Event.init))))
    } catch {
      logEventDatabaseError(
        "event.list_failed",
        "Failed to fetch events",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func createEvent(
    _ input: Operations.CreateEvent.Input
  ) async throws -> Operations.CreateEvent.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard case .json(let body) = input.body else {
      return .badRequest
    }
    let eventID = UUID(uuidString: UUID.uuidV7String())!
    guard let revision = eventRevisionRecord(from: body, eventID: eventID) else {
      return .badRequest
    }
    let event = EventRecord(id: eventID, organizerUserID: userID, createdAt: Date())

    do {
      if let imageID = revision.imageID {
        guard try await ownedImageExists(imageID: imageID, userID: userID) else {
          return .badRequest
        }
      }
      try await database.write { db in
        try await EventRecord.insert { event }.execute(db)
        try await EventRevisionRecord.insert { revision }.execute(db)
      }
      return .ok(.init(body: .json(.init(.init(event: event, revision: revision)))))
    } catch {
      logEventDatabaseError(
        "event.create_failed",
        "Failed to create event",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func getEvent(
    _ input: Operations.GetEvent.Input
  ) async throws -> Operations.GetEvent.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard let eventID = UUID(uuidString: input.path.eventId) else {
      return .badRequest
    }

    do {
      guard let event = try await latestEventSnapshot(eventID: eventID) else {
        return .notFound
      }
      guard try await canViewEvent(event, userID: userID) else {
        return .notFound
      }
      return .ok(.init(body: .json(.init(event))))
    } catch {
      logEventDatabaseError(
        "event.read_failed",
        "Failed to fetch event",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func updateEvent(
    _ input: Operations.UpdateEvent.Input
  ) async throws -> Operations.UpdateEvent.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      case .json(let body) = input.body
    else {
      return .badRequest
    }

    do {
      guard let current = try await latestEventSnapshot(eventID: eventID),
        current.event.organizerUserID == userID
      else {
        return .notFound
      }
      guard
        let revision = eventRevisionRecord(
          from: body,
          eventID: eventID,
          preservingLifecycleFrom: current.revision
        )
      else {
        return .badRequest
      }
      if let imageID = revision.imageID {
        guard try await ownedImageExists(imageID: imageID, userID: userID) else {
          return .badRequest
        }
      }
      try await database.write { db in
        try await EventRevisionRecord.insert { revision }.execute(db)
      }
      return .ok(.init(body: .json(.init(.init(event: current.event, revision: revision)))))
    } catch {
      logEventDatabaseError(
        "event.update_failed",
        "Failed to update event",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func registerEventParticipant(
    _ input: Operations.RegisterEventParticipant.Input
  ) async throws -> Operations.RegisterEventParticipant.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard let eventID = UUID(uuidString: input.path.eventId) else {
      return .badRequest
    }

    do {
      let participant: EventParticipantRecord? = try await database.withTransaction { db in
        try await lockEventRegistration(eventID: eventID, db: db)
        guard let event = try await latestEventSnapshot(eventID: eventID, db: db),
          canRegisterEvent(event, userID: userID, now: Date())
        else {
          return nil
        }
        if let participant = try await eventParticipant(eventID: eventID, userID: userID, db: db) {
          switch participant.status {
          case .registered, .waitlisted, .attended:
            return participant
          case .canceled:
            throw EventRegistrationError.canceledParticipant
          }
        }

        let participantStatus: EventParticipantRecord.Status
        if let capacity = event.revision.capacity {
          let activeParticipantCount = try await activeParticipantCount(eventID: eventID, db: db)
          participantStatus = activeParticipantCount < capacity ? .registered : .waitlisted
        } else {
          participantStatus = .registered
        }

        let participant = EventParticipantRecord(
          id: UUID(uuidString: UUID.uuidV7String())!,
          eventID: eventID,
          userID: userID,
          status: participantStatus,
          createdAt: Date()
        )
        try await EventParticipantRecord.insert { participant }.execute(db)
        return participant
      }
      guard let participant
      else {
        return .notFound
      }
      return .ok(.init(body: .json(.init(participant))))
    } catch EventRegistrationError.canceledParticipant {
      return .badRequest
    } catch {
      logEventDatabaseError(
        "event.participant_register_failed",
        "Failed to register event participant",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func createEventQuestion(
    _ input: Operations.CreateEventQuestion.Input
  ) async throws -> Operations.CreateEventQuestion.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard let eventID = UUID(uuidString: input.path.eventId), case .json(let body) = input.body
    else {
      return .badRequest
    }
    let (imageID, validImageID) = parseOptionalUUID(body.imageID)
    guard validImageID, body.questionNumber > 0 else {
      return .badRequest
    }

    do {
      guard try await isEventOrganizer(eventID: eventID, userID: userID) else {
        return .notFound
      }
      if let imageID {
        guard try await ownedImageExists(imageID: imageID, userID: userID) else {
          return .badRequest
        }
      }
      let question = EventQuestionRecord(
        id: UUID(uuidString: UUID.uuidV7String())!,
        eventID: eventID,
        questionNumber: Int(body.questionNumber),
        createdAt: Date()
      )
      let revision = EventQuestionRevisionRecord(
        id: UUID(uuidString: UUID.uuidV7String())!,
        eventQuestionID: question.id,
        imageID: imageID,
        note: body.note,
        createdAt: Date()
      )
      try await database.write { db in
        try await EventQuestionRecord.insert { question }.execute(db)
        try await EventQuestionRevisionRecord.insert { revision }.execute(db)
      }
      return .ok(.init(body: .json(.init(.init(question: question, revision: revision)))))
    } catch {
      logEventDatabaseError(
        "event.question_create_failed",
        "Failed to create event question",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func updateEventQuestion(
    _ input: Operations.UpdateEventQuestion.Input
  ) async throws -> Operations.UpdateEventQuestion.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      let questionID = UUID(uuidString: input.path.questionId),
      case .json(let body) = input.body
    else {
      return .badRequest
    }
    let (imageID, validImageID) = parseOptionalUUID(body.imageID)
    guard validImageID, body.questionNumber > 0 else {
      return .badRequest
    }

    do {
      guard try await isEventOrganizer(eventID: eventID, userID: userID),
        let question = try await eventQuestion(questionID: questionID, eventID: eventID)
      else {
        return .notFound
      }
      guard question.questionNumber == Int(body.questionNumber) else {
        return .badRequest
      }
      if let imageID {
        guard try await ownedImageExists(imageID: imageID, userID: userID) else {
          return .badRequest
        }
      }
      let revision = EventQuestionRevisionRecord(
        id: UUID(uuidString: UUID.uuidV7String())!,
        eventQuestionID: questionID,
        imageID: imageID,
        note: body.note,
        createdAt: Date()
      )
      try await database.write { db in
        try await EventQuestionRevisionRecord.insert { revision }.execute(db)
      }
      return .ok(.init(body: .json(.init(.init(question: question, revision: revision)))))
    } catch {
      logEventDatabaseError(
        "event.question_update_failed",
        "Failed to update event question",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func createEventQuestionCorrectAnswer(
    _ input: Operations.CreateEventQuestionCorrectAnswer.Input
  ) async throws -> Operations.CreateEventQuestionCorrectAnswer.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      let questionID = UUID(uuidString: input.path.questionId),
      case .json(let body) = input.body,
      let varietyIDs = parseUUIDs(body.wineVarietyIDs)
    else {
      return .badRequest
    }
    let (styleID, validStyleID) = parseOptionalUUID(body.wineStyleID)
    let (regionID, validRegionID) = parseOptionalUUID(body.wineRegionID)
    guard validStyleID, validRegionID, isValidAlcoholByVolume(body.alcoholByVolume) else {
      return .badRequest
    }

    do {
      guard try await isEventOrganizer(eventID: eventID, userID: userID),
        try await eventQuestionExists(questionID: questionID, eventID: eventID)
      else {
        return .notFound
      }
      let answer = try await insertCorrectAnswer(
        questionID: questionID,
        styleID: styleID,
        regionID: regionID,
        vintage: body.vintage.map(Int.init),
        alcoholByVolume: body.alcoholByVolume,
        varietyIDs: varietyIDs,
        requireNoExistingAnswer: true
      )
      return .ok(.init(body: .json(.init(answer, wineVarietyIDs: varietyIDs))))
    } catch EventRevisionMutationError.alreadyExists {
      return .badRequest
    } catch {
      logEventDatabaseError(
        "event.correct_answer_create_failed",
        "Failed to create correct answer",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func updateEventQuestionCorrectAnswer(
    _ input: Operations.UpdateEventQuestionCorrectAnswer.Input
  ) async throws -> Operations.UpdateEventQuestionCorrectAnswer.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      let questionID = UUID(uuidString: input.path.questionId),
      case .json(let body) = input.body,
      let varietyIDs = parseUUIDs(body.wineVarietyIDs)
    else {
      return .badRequest
    }
    let (styleID, validStyleID) = parseOptionalUUID(body.wineStyleID)
    let (regionID, validRegionID) = parseOptionalUUID(body.wineRegionID)
    guard validStyleID, validRegionID, isValidAlcoholByVolume(body.alcoholByVolume) else {
      return .badRequest
    }

    do {
      guard try await isEventOrganizer(eventID: eventID, userID: userID),
        try await eventQuestionExists(questionID: questionID, eventID: eventID)
      else {
        return .notFound
      }

      let answer = try await insertCorrectAnswer(
        questionID: questionID,
        styleID: styleID,
        regionID: regionID,
        vintage: body.vintage.map(Int.init),
        alcoholByVolume: body.alcoholByVolume,
        varietyIDs: varietyIDs
      )
      return .ok(.init(body: .json(.init(answer, wineVarietyIDs: varietyIDs))))
    } catch {
      logEventDatabaseError(
        "event.correct_answer_update_failed",
        "Failed to update correct answer",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func createEventQuestionResponse(
    _ input: Operations.CreateEventQuestionResponse.Input
  ) async throws -> Operations.CreateEventQuestionResponse.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      let questionID = UUID(uuidString: input.path.questionId),
      case .json(let body) = input.body,
      let varietyIDs = parseUUIDs(body.wineVarietyIDs)
    else {
      return .badRequest
    }
    let (styleID, validStyleID) = parseOptionalUUID(body.wineStyleID)
    let (regionID, validRegionID) = parseOptionalUUID(body.wineRegionID)
    guard validStyleID, validRegionID, isValidAlcoholByVolume(body.alcoholByVolume) else {
      return .badRequest
    }

    do {
      guard try await eventQuestionExists(questionID: questionID, eventID: eventID),
        try await canSubmitResponse(eventID: eventID, userID: userID)
      else {
        return .notFound
      }
      let response = try await insertQuestionResponse(
        questionID: questionID,
        userID: userID,
        styleID: styleID,
        regionID: regionID,
        vintage: body.vintage.map(Int.init),
        alcoholByVolume: body.alcoholByVolume,
        note: body.note,
        varietyIDs: varietyIDs,
        requireNoExistingResponse: true
      )
      return .ok(.init(body: .json(.init(response, wineVarietyIDs: varietyIDs))))
    } catch EventRevisionMutationError.alreadyExists {
      return .badRequest
    } catch {
      logEventDatabaseError(
        "event.response_create_failed",
        "Failed to create event response",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func updateMyEventQuestionResponse(
    _ input: Operations.UpdateMyEventQuestionResponse.Input
  ) async throws -> Operations.UpdateMyEventQuestionResponse.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      let questionID = UUID(uuidString: input.path.questionId),
      case .json(let body) = input.body,
      let varietyIDs = parseUUIDs(body.wineVarietyIDs)
    else {
      return .badRequest
    }
    let (styleID, validStyleID) = parseOptionalUUID(body.wineStyleID)
    let (regionID, validRegionID) = parseOptionalUUID(body.wineRegionID)
    guard validStyleID, validRegionID, isValidAlcoholByVolume(body.alcoholByVolume) else {
      return .badRequest
    }

    do {
      guard try await eventQuestionExists(questionID: questionID, eventID: eventID),
        try await canSubmitResponse(eventID: eventID, userID: userID)
      else {
        return .notFound
      }

      let response = try await insertQuestionResponse(
        questionID: questionID,
        userID: userID,
        styleID: styleID,
        regionID: regionID,
        vintage: body.vintage.map(Int.init),
        alcoholByVolume: body.alcoholByVolume,
        note: body.note,
        varietyIDs: varietyIDs
      )
      return .ok(.init(body: .json(.init(response, wineVarietyIDs: varietyIDs))))
    } catch {
      logEventDatabaseError(
        "event.response_update_failed",
        "Failed to update event response",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }
}

extension API {
  func getWineStyles(
    _ input: Operations.GetWineStyles.Input
  ) async throws -> Operations.GetWineStyles.Output {
    guard UserTokenContext.currentUserID != nil else { return .unauthorized }
    do {
      let styles = try await database.read { db in
        try await WineStyleRecord.order { $0.name }.fetchAll(db)
      }
      return .ok(.init(body: .json(styles.map(Components.Schemas.WineStyle.init))))
    } catch {
      return .badRequest
    }
  }

  func getWineVarieties(
    _ input: Operations.GetWineVarieties.Input
  ) async throws -> Operations.GetWineVarieties.Output {
    guard UserTokenContext.currentUserID != nil else { return .unauthorized }
    do {
      let varieties = try await database.read { db in
        let varieties = try await WineVarietyRecord.order { $0.name }.fetchAll(db)
        let styleLinks = try await WineVarietyStyleRecord.fetchAll(db)
        let styleIDsByVarietyID = Dictionary(grouping: styleLinks, by: \.wineVarietyID)
          .mapValues { links in
            links.map(\.wineStyleID).sorted { $0.uuidString < $1.uuidString }
          }
        return varieties.map { variety in
          (variety, styleIDsByVarietyID[variety.id, default: []])
        }
      }
      return .ok(
        .init(
          body: .json(
            varieties.map { variety, wineStyleIDs in
              Components.Schemas.WineVariety(variety, wineStyleIDs: wineStyleIDs)
            }
          )
        )
      )
    } catch {
      return .badRequest
    }
  }

  func getWineRegionTypes(
    _ input: Operations.GetWineRegionTypes.Input
  ) async throws -> Operations.GetWineRegionTypes.Output {
    guard UserTokenContext.currentUserID != nil else { return .unauthorized }
    do {
      let types = try await database.read { db in
        try await WineRegionTypeRecord.order { $0.name }.fetchAll(db)
      }
      return .ok(.init(body: .json(types.map(Components.Schemas.WineRegionType.init))))
    } catch {
      return .badRequest
    }
  }

  func getWineRegions(
    _ input: Operations.GetWineRegions.Input
  ) async throws -> Operations.GetWineRegions.Output {
    guard UserTokenContext.currentUserID != nil else { return .unauthorized }
    do {
      let regions = try await database.read { db in
        try await WineRegionRecord.order { $0.name }.fetchAll(db)
      }
      return .ok(.init(body: .json(regions.map(Components.Schemas.WineRegion.init))))
    } catch {
      return .badRequest
    }
  }
}

extension API {
  fileprivate func eventRevisionRecord(
    from body: Components.Schemas.CreateEventRequest,
    eventID: UUID,
    preservingLifecycleFrom currentRevision: EventRevisionRecord? = nil
  ) -> EventRevisionRecord? {
    let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let venueName = body.venueName.trimmingCharacters(in: .whitespacesAndNewlines)
    let addressLine1 = body.venueAddress.addressLine1.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let countryCode = body.venueAddress.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    guard !title.isEmpty, !venueName.isEmpty, !addressLine1.isEmpty, countryCode.count == 2 else {
      return nil
    }
    guard body.eventPeriod.startsAt < body.eventPeriod.endsAt else { return nil }
    if let registrationPeriod = body.registrationPeriod,
      registrationPeriod.startsAt >= registrationPeriod.endsAt
    {
      return nil
    }
    if let capacity = body.capacity, capacity <= 0 { return nil }
    if let entryFee = body.entryFee,
      entryFee.minorAmount < 0
        || entryFee.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 3
    {
      return nil
    }
    if let coordinate = body.venueCoordinate,
      coordinate.latitude < -90 || coordinate.latitude > 90
        || coordinate.longitude < -180 || coordinate.longitude > 180
    {
      return nil
    }
    guard let visibility = EventRecord.Visibility(rawValue: body.visibility.rawValue) else {
      return nil
    }
    let (imageID, validImageID) = parseOptionalUUID(body.imageID)
    guard validImageID else { return nil }

    return EventRevisionRecord(
      id: UUID(uuidString: UUID.uuidV7String())!,
      eventID: eventID,
      title: title,
      body: body.body,
      imageID: imageID,
      venueName: venueName,
      venueAddressLine1: addressLine1,
      venueAddressLine2: trimmedOptional(body.venueAddress.addressLine2),
      venueLocality: trimmedOptional(body.venueAddress.locality),
      venueAdministrativeArea: trimmedOptional(body.venueAddress.administrativeArea),
      venuePostalCode: trimmedOptional(body.venueAddress.postalCode),
      venueCountryCode: countryCode,
      venueLatitude: body.venueCoordinate?.latitude,
      venueLongitude: body.venueCoordinate?.longitude,
      registrationStartsAt: body.registrationPeriod.map {
        Date(timeIntervalSinceReferenceDate: $0.startsAt)
      },
      registrationEndsAt: body.registrationPeriod.map {
        Date(timeIntervalSinceReferenceDate: $0.endsAt)
      },
      startsAt: Date(timeIntervalSinceReferenceDate: body.eventPeriod.startsAt),
      endsAt: Date(timeIntervalSinceReferenceDate: body.eventPeriod.endsAt),
      answersPublishedAt: body.answersPublishedAt.map(Date.init(timeIntervalSinceReferenceDate:))
        ?? currentRevision?.answersPublishedAt,
      capacity: body.capacity.map(Int.init),
      entryFeeMinorAmount: body.entryFee.map { Int($0.minorAmount) },
      entryFeeCurrencyCode: body.entryFee?.currencyCode.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).uppercased(),
      visibility: visibility,
      publishedAt: body.publishedAt.map(Date.init(timeIntervalSinceReferenceDate:))
        ?? currentRevision?.publishedAt,
      canceledAt: body.canceledAt.map(Date.init(timeIntervalSinceReferenceDate:))
        ?? currentRevision?.canceledAt,
      createdAt: Date()
    )
  }

  fileprivate func latestEventsVisible(to userID: UUID) async throws -> [EventSnapshot] {
    try await database.read { db in
      let rows =
        try await EventRecord
        .joinLateral { event in
          EventRevisionRecord
            .where { $0.eventID.eq(event.id) }
            .order { ($0.createdAt.desc(), $0.id.desc()) }
            .limit(1)
        }
        .where { event, revision in
          event.organizerUserID.eq(userID)
            .or(
              revision.visibility.eq(EventRecord.Visibility.public)
                .and(revision.publishedAt.isNot(nil))
                .and(revision.canceledAt.is(nil))
            )
        }
        .order { event, revision in
          (revision.startsAt.desc(), event.id.desc())
        }
        .selectStar()
        .fetchAll(db)
      return rows.map { event, revision in
        EventSnapshot(event: event, revision: revision)
      }
    }
  }

  fileprivate func latestEventSnapshot(eventID: UUID) async throws -> EventSnapshot? {
    try await database.read { db in
      try await latestEventSnapshot(eventID: eventID, db: db)
    }
  }

  fileprivate func latestEventSnapshot(
    eventID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws -> EventSnapshot? {
    let row =
      try await EventRecord
      .where { $0.id.eq(eventID) }
      .joinLateral { event in
        EventRevisionRecord
          .where { $0.eventID.eq(event.id) }
          .order { ($0.createdAt.desc(), $0.id.desc()) }
          .limit(1)
      }
      .selectStar()
      .limit(1)
      .fetchAll(db)
      .first
    return row.map { event, revision in
      EventSnapshot(event: event, revision: revision)
    }
  }

  fileprivate func canViewEvent(_ event: EventSnapshot, userID: UUID) async throws -> Bool {
    if event.event.organizerUserID == userID {
      return true
    }
    guard event.revision.publishedAt != nil, event.revision.canceledAt == nil else {
      return false
    }
    if event.revision.visibility != .private {
      return true
    }
    return try await activeParticipantExists(eventID: event.event.id, userID: userID)
  }

  fileprivate func canRegisterEvent(
    _ event: EventSnapshot,
    userID: UUID,
    now: Date
  ) -> Bool {
    guard event.revision.canceledAt == nil else {
      return false
    }
    if event.event.organizerUserID == userID {
      return true
    }
    guard event.revision.publishedAt != nil, event.revision.visibility != .private else {
      return false
    }
    if let registrationStartsAt = event.revision.registrationStartsAt, now < registrationStartsAt {
      return false
    }
    if let registrationEndsAt = event.revision.registrationEndsAt, now >= registrationEndsAt {
      return false
    }
    return true
  }

  fileprivate func canSubmitResponse(eventID: UUID, userID: UUID) async throws -> Bool {
    guard let event = try await latestEventSnapshot(eventID: eventID) else {
      return false
    }
    let now = Date()
    guard event.revision.canceledAt == nil,
      now >= event.revision.startsAt,
      now < event.revision.endsAt
    else {
      return false
    }
    if event.event.organizerUserID == userID {
      return true
    }
    guard event.revision.publishedAt != nil else {
      return false
    }
    let hasActiveParticipant = try await activeParticipantExists(eventID: eventID, userID: userID)
    guard event.revision.visibility != .private || hasActiveParticipant else {
      return false
    }
    return hasActiveParticipant
  }

  fileprivate func activeParticipantExists(eventID: UUID, userID: UUID) async throws -> Bool {
    try await database.read { db in
      let participant =
        try await EventParticipantRecord
        .where {
          $0.eventID.eq(eventID)
            .and($0.userID.eq(userID))
            .and($0.status.in([EventParticipantRecord.Status.registered, .attended]))
        }
        .limit(1)
        .fetchOne(db)
      return participant != nil
    }
  }

  fileprivate func eventParticipant(
    eventID: UUID,
    userID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws -> EventParticipantRecord? {
    try await EventParticipantRecord
      .where {
        $0.eventID.eq(eventID)
          .and($0.userID.eq(userID))
      }
      .limit(1)
      .fetchOne(db)
  }

  fileprivate func activeParticipantCount(
    eventID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws -> Int {
    try await EventParticipantRecord
      .where {
        $0.eventID.eq(eventID)
          .and($0.status.in([EventParticipantRecord.Status.registered, .attended]))
      }
      .fetchCount(db)
  }

  fileprivate func lockEventRegistration(
    eventID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws {
    let query: QueryFragment =
      "SELECT id FROM public.events WHERE id = \(eventID, as: UUID.self) FOR UPDATE"
    try await db.executeFragment(query)
  }

  fileprivate func lockEventQuestion(
    questionID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws {
    let query: QueryFragment =
      "SELECT id FROM public.event_questions WHERE id = \(questionID, as: UUID.self) FOR UPDATE"
    try await db.executeFragment(query)
  }

  fileprivate func ownedImageExists(
    imageID: UUID,
    userID: UUID
  ) async throws -> Bool {
    try await database.read { db in
      let image =
        try await ImageRecord
        .where {
          $0.id.eq(imageID)
            .and($0.userID.eq(userID))
        }
        .limit(1)
        .fetchOne(db)
      return image != nil
    }
  }

  fileprivate func isEventOrganizer(
    eventID: UUID,
    userID: UUID
  ) async throws -> Bool {
    try await database.read { db in
      let event =
        try await EventRecord
        .where {
          $0.id.eq(eventID)
            .and($0.organizerUserID.eq(userID))
        }
        .limit(1)
        .fetchOne(db)
      return event != nil
    }
  }

  fileprivate func eventQuestionExists(
    questionID: UUID,
    eventID: UUID
  ) async throws -> Bool {
    try await eventQuestion(questionID: questionID, eventID: eventID) != nil
  }

  fileprivate func eventQuestion(
    questionID: UUID,
    eventID: UUID
  ) async throws -> EventQuestionRecord? {
    try await database.read { db in
      try await EventQuestionRecord
        .where {
          $0.id.eq(questionID)
            .and($0.eventID.eq(eventID))
        }
        .limit(1)
        .fetchOne(db)
    }
  }

  fileprivate func eventQuestionCorrectAnswerExists(
    questionID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws -> Bool {
    let answer =
      try await EventQuestionCorrectAnswerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .limit(1)
      .fetchOne(db)
    return answer != nil
  }

  fileprivate func eventQuestionResponseExists(
    questionID: UUID,
    userID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws -> Bool {
    let response =
      try await EventQuestionResponseRecord
      .where {
        $0.eventQuestionID.eq(questionID)
          .and($0.userID.eq(userID))
      }
      .limit(1)
      .fetchOne(db)
    return response != nil
  }

  fileprivate func insertCorrectAnswer(
    questionID: UUID,
    styleID: UUID?,
    regionID: UUID?,
    vintage: Int?,
    alcoholByVolume: Double?,
    varietyIDs: [UUID],
    requireNoExistingAnswer: Bool = false
  ) async throws -> EventQuestionCorrectAnswerRecord {
    let answer = EventQuestionCorrectAnswerRecord(
      id: UUID(uuidString: UUID.uuidV7String())!,
      eventQuestionID: questionID,
      wineStyleID: styleID,
      wineRegionID: regionID,
      vintage: vintage,
      alcoholByVolume: alcoholByVolume,
      createdAt: Date()
    )
    try await database.withTransaction { db in
      if requireNoExistingAnswer {
        try await lockEventQuestion(questionID: questionID, db: db)
        guard try await eventQuestionCorrectAnswerExists(questionID: questionID, db: db) == false
        else {
          throw EventRevisionMutationError.alreadyExists
        }
      }
      try await EventQuestionCorrectAnswerRecord.insert { answer }.execute(db)
      let answerVarieties = varietyIDs.map { varietyID in
        EventQuestionCorrectAnswerVarietyRecord(
          eventQuestionCorrectAnswerID: answer.id,
          wineVarietyID: varietyID,
          createdAt: Date()
        )
      }
      if !answerVarieties.isEmpty {
        try await EventQuestionCorrectAnswerVarietyRecord.insert { answerVarieties }.execute(db)
      }
    }
    return answer
  }

  fileprivate func insertQuestionResponse(
    questionID: UUID,
    userID: UUID,
    styleID: UUID?,
    regionID: UUID?,
    vintage: Int?,
    alcoholByVolume: Double?,
    note: String?,
    varietyIDs: [UUID],
    requireNoExistingResponse: Bool = false
  ) async throws -> EventQuestionResponseRecord {
    let response = EventQuestionResponseRecord(
      id: UUID(uuidString: UUID.uuidV7String())!,
      eventQuestionID: questionID,
      userID: userID,
      wineStyleID: styleID,
      wineRegionID: regionID,
      vintage: vintage,
      alcoholByVolume: alcoholByVolume,
      note: note,
      submittedAt: Date()
    )
    try await database.withTransaction { db in
      if requireNoExistingResponse {
        try await lockEventQuestion(questionID: questionID, db: db)
        guard
          try await eventQuestionResponseExists(
            questionID: questionID,
            userID: userID,
            db: db
          ) == false
        else {
          throw EventRevisionMutationError.alreadyExists
        }
      }
      try await EventQuestionResponseRecord.insert { response }.execute(db)
      let responseVarieties = varietyIDs.map { varietyID in
        EventQuestionResponseVarietyRecord(
          eventQuestionResponseID: response.id,
          wineVarietyID: varietyID,
          createdAt: Date()
        )
      }
      if !responseVarieties.isEmpty {
        try await EventQuestionResponseVarietyRecord.insert { responseVarieties }.execute(db)
      }
    }
    return response
  }

  fileprivate func parseOptionalUUID(_ string: String?) -> (id: UUID?, isValid: Bool) {
    guard let string else { return (nil, true) }
    guard let id = UUID(uuidString: string) else { return (nil, false) }
    return (id, true)
  }

  fileprivate func parseUUIDs(_ strings: [String]) -> [UUID]? {
    let ids = strings.compactMap(UUID.init(uuidString:))
    return ids.count == strings.count ? ids : nil
  }

  fileprivate func trimmedOptional(_ string: String?) -> String? {
    guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }

  fileprivate func isValidAlcoholByVolume(_ alcoholByVolume: Double?) -> Bool {
    guard let alcoholByVolume else { return true }
    return alcoholByVolume >= 0
  }

  fileprivate func logEventDatabaseError(
    _ eventName: String,
    _ message: Logger.Message,
    userID: UUID,
    error: any Error
  ) {
    AppRequestContext.current?.logger.appError(
      eventName: eventName,
      message,
      metadata: AppLogMetadata.userID(userID).merging([
        "db.operation": .string("event")
      ]) { _, new in new },
      error: error
    )
  }
}

extension Components.Schemas.Event {
  fileprivate init(_ snapshot: EventSnapshot) {
    let event = snapshot.event
    let revision = snapshot.revision
    let venueAddress = Components.Schemas.PostalAddress(
      addressLine1: revision.venueAddressLine1,
      addressLine2: revision.venueAddressLine2,
      locality: revision.venueLocality,
      administrativeArea: revision.venueAdministrativeArea,
      postalCode: revision.venuePostalCode,
      countryCode: revision.venueCountryCode
    )
    let venueCoordinate: Components.Schemas.GeoCoordinate? = revision.venueLatitude.flatMap {
      latitude in
      revision.venueLongitude.map { longitude in
        Components.Schemas.GeoCoordinate(latitude: latitude, longitude: longitude)
      }
    }
    let registrationPeriod: Components.Schemas.DateTimePeriod? = revision.registrationStartsAt
      .flatMap { startsAt in
        revision.registrationEndsAt.map { endsAt in
          Components.Schemas.DateTimePeriod(
            startsAt: startsAt.timeIntervalSinceReferenceDate,
            endsAt: endsAt.timeIntervalSinceReferenceDate
          )
        }
      }
    let eventPeriod = Components.Schemas.DateTimePeriod(
      startsAt: revision.startsAt.timeIntervalSinceReferenceDate,
      endsAt: revision.endsAt.timeIntervalSinceReferenceDate
    )
    let entryFee: Components.Schemas.Money? = revision.entryFeeMinorAmount.flatMap { amount in
      revision.entryFeeCurrencyCode.map { currencyCode in
        Components.Schemas.Money(minorAmount: Int64(amount), currencyCode: currencyCode)
      }
    }
    let visibility = Components.Schemas.EventVisibility(rawValue: revision.visibility.rawValue)!

    self.init(
      id: event.id.uuidString,
      organizerUserID: event.organizerUserID.uuidString,
      title: revision.title,
      body: revision.body,
      imageID: revision.imageID?.uuidString,
      venueName: revision.venueName,
      venueAddress: venueAddress,
      venueCoordinate: venueCoordinate,
      registrationPeriod: registrationPeriod,
      eventPeriod: eventPeriod,
      answersPublishedAt: revision.answersPublishedAt?.timeIntervalSinceReferenceDate,
      capacity: revision.capacity.map(Int32.init),
      entryFee: entryFee,
      visibility: visibility,
      publishedAt: revision.publishedAt?.timeIntervalSinceReferenceDate,
      canceledAt: revision.canceledAt?.timeIntervalSinceReferenceDate,
      createdAt: event.createdAt.timeIntervalSinceReferenceDate
    )
  }
}

extension Components.Schemas.EventParticipant {
  init(_ participant: EventParticipantRecord) {
    self.init(
      id: participant.id.uuidString,
      eventID: participant.eventID.uuidString,
      userID: participant.userID.uuidString,
      status: Components.Schemas.EventParticipantStatus(rawValue: participant.status.rawValue)!,
      createdAt: participant.createdAt.timeIntervalSinceReferenceDate
    )
  }
}

extension Components.Schemas.EventQuestion {
  fileprivate init(_ snapshot: EventQuestionSnapshot) {
    let question = snapshot.question
    let revision = snapshot.revision
    self.init(
      id: question.id.uuidString,
      eventID: question.eventID.uuidString,
      questionNumber: Int32(question.questionNumber),
      imageID: revision.imageID?.uuidString,
      note: revision.note,
      createdAt: question.createdAt.timeIntervalSinceReferenceDate
    )
  }
}

extension Components.Schemas.EventQuestionCorrectAnswer {
  init(_ answer: EventQuestionCorrectAnswerRecord, wineVarietyIDs: [UUID]) {
    self.init(
      id: answer.id.uuidString,
      eventQuestionID: answer.eventQuestionID.uuidString,
      wineStyleID: answer.wineStyleID?.uuidString,
      wineRegionID: answer.wineRegionID?.uuidString,
      vintage: answer.vintage.map(Int32.init),
      alcoholByVolume: answer.alcoholByVolume,
      wineVarietyIDs: wineVarietyIDs.map(\.uuidString),
      createdAt: answer.createdAt.timeIntervalSinceReferenceDate
    )
  }
}

extension Components.Schemas.EventQuestionResponse {
  init(_ response: EventQuestionResponseRecord, wineVarietyIDs: [UUID]) {
    self.init(
      id: response.id.uuidString,
      eventQuestionID: response.eventQuestionID.uuidString,
      userID: response.userID.uuidString,
      wineStyleID: response.wineStyleID?.uuidString,
      wineRegionID: response.wineRegionID?.uuidString,
      vintage: response.vintage.map(Int32.init),
      alcoholByVolume: response.alcoholByVolume,
      note: response.note,
      wineVarietyIDs: wineVarietyIDs.map(\.uuidString),
      submittedAt: response.submittedAt.timeIntervalSinceReferenceDate
    )
  }
}

extension Components.Schemas.WineStyle {
  init(_ style: WineStyleRecord) {
    self.init(id: style.id.uuidString, code: style.code, name: style.name)
  }
}

extension Components.Schemas.WineVariety {
  init(_ variety: WineVarietyRecord, wineStyleIDs: [UUID]) {
    self.init(
      id: variety.id.uuidString,
      name: variety.name,
      wineStyleIDs: wineStyleIDs.map(\.uuidString)
    )
  }
}

extension Components.Schemas.WineRegionType {
  init(_ type: WineRegionTypeRecord) {
    self.init(id: type.id.uuidString, code: type.code, name: type.name)
  }
}

extension Components.Schemas.WineRegion {
  init(_ region: WineRegionRecord) {
    self.init(
      id: region.id.uuidString,
      parentRegionID: region.parentRegionID?.uuidString,
      wineRegionTypeID: region.wineRegionTypeID.uuidString,
      name: region.name
    )
  }
}
