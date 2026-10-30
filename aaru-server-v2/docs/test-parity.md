# Swift → Go test parity

Every `@Test` in `aaru-server/Tests/AppTests` (the Swift server, archived) mapped to the Go test
under `internal/` that covers the same behaviour (route, assertions, messages). Go paths are
relative to `internal/`. Names differ; the match is on behaviour.

Notes: **ported** means the Go test was added for this mapping; **extended** means an existing Go
test gained the Swift assertions it lacked; **N/A** says why the test has no Go counterpart.
Helpers (`TestSupport*`, `TestFakes`, `LibraryHarness`, `*+Fake*`) hold no tests.

107 files, 615 tests: 73 ported, 15 extended, 1 N/A.

## AgentTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| wireBody | model/anthropic_parity_test.go:TestMessagesWireBodyAndReplyParse<br>model/anthropic_test.go:TestBodyHasNoSamplingFieldsOrPrefill | ported (x-api-key, no workspace header, usage-limit 400, end_turn, thinking kept) |
| workspaceHeader | model/anthropic_parity_test.go:TestMessagesSendsTheWorkspaceID<br>model/anthropic_test.go:TestCompleteSendsHeadersAndParses | ported |
| toolsRead | httpapi/agent_reply_test.go:TestAgentToolsOnlyRead | |
| reply | httpapi/agent_reply_test.go:TestAgentReplyUsesOnlyTheTaggersLibrary | |
| caps | httpapi/agent_reply_test.go:TestAgentOverTheHourlyCapRestsOnceWithoutAModelCall | |
| refusalAndFailure | httpapi/agent_reply_test.go:TestAgentRefusalGetsAShortReply<br>httpapi/agent_reply_test.go:TestAgentRepeatedFailuresEndInOneApology | |
| disabled | httpapi/agent_reply_test.go:TestAgentDisabledWithoutAModel | |

## AgentTokenTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| lifecycle | httpapi/agent_token_test.go:TestAgentTokenLifecycleShowsTheSecretOnceAndNeverStoresIt | |
| scopesAndOwnership | httpapi/agent_token_test.go:TestLibraryWritesAreOptInAndAnotherUserCannotRevoke | |
| mcpTokens | httpapi/agent_token_test.go:TestMCPTokensHaveTheirOwnPrefixScopesSetupAndList<br>httpapi/agent_parity_test.go:TestMCPTokenIsReadOnlyByDefaultAndNoStremioLink | extended: default scopes `library:read`, MCP secret 404s on /stremio |
| redaction | middleware/log_parity_test.go:TestRequestLogsNeverCarryAStremioTokenOrCallbackSecrets | ported |
| responseMilliseconds | middleware/log_parity_test.go:TestResponseLogsGiveWholeMilliseconds | ported (logged `hb.response.ms` is an int64) |

## AnimeListImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| malParser | `imports/parsers_test.go:TestMALParser` |  |
| onHoldMapping | `imports/parsers_test.go:TestAnimeOnHoldMapping` |  |
| anilistReader | `imports/anilist_rows_test.go:TestAniListRows` |  |
| malUploadFlow | `httpapi/imports_parsers_test.go:TestMALUploadFlow` |  |
| anilistCreate | `httpapi/imports_parsers_test.go:TestAniListCreate` |  |

## AnimeMappingLoaderTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| parse | `catalog/animemappings_test.go:TestParseAnimeMappings` |  |
| loadAndResolve | `catalog/animemappings_test.go:TestAnimeMappingsLoadTwiceAndResolve` |  |

## APITests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `healthOK` | httpapi/router_test.go:TestHealthAnswersWithoutSession | |
| `healthUnavailable` | httpapi/api_parity_test.go:TestHealthIs503WithNoDetailWhenTheDatabaseIsDown | ported |
| `notFoundShape` | httpapi/api_parity_test.go:TestAnUnknownRouteIs404InTheSharedShape<br>httpapi/router_test.go:TestUnknownRouteIsNotFoundShape | ported |
| `anonymousIsUnauthorized` | httpapi/api_parity_test.go:TestAnonymousV1IsUnauthorizedWhetherOrNotTheRouteExists<br>httpapi/router_test.go:TestPrivateRouteNeedsSession | ported |
| `validationShape` | middleware/errors_parity_test.go:TestAValidationFailureIs422NamingTheField | ported |
| `internalErrorIsOpaque` | middleware/errors_parity_test.go:TestAnUnexpectedErrorIsAnOpaque500 | ported |
| `missingTMDBKey` | config/config_parity_test.go:TestServingWithoutTheTMDBKeyFailsNamingIt | ported |
| `noRequestInLogs` | middleware/errors_parity_test.go:TestA5xxLogLineNeverCarriesTheRequest<br>middleware/errors_test.go:TestProviderFailureNamesTheSwiftCase | ported (ErrorLoggingTests suite) |

## AppleVerifierTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| validToken | auth/verifiers_test.go:TestAppleValidTokenYieldsSubjectLowercasedEmailAndRelayFlag | |
| expired | auth/verifiers_test.go:TestAppleExpiredTokenIsRejected | |
| rotatedKeyRefresh | auth/verifiers_test.go:TestAppleRotatedKeyIsPickedUpByOneRefresh | |
| audienceAndNonce | auth/verifiers_test.go:TestAppleOtherAudienceOrWrongNonceIsRejected | |
| unknownKid | auth/verifiers_test.go:TestAppleUnknownKidRefreshesOnceThenFailsClosed | |

## AuthFlowTests+EmailCode.swift

| Swift test | Go test | note |
| --- | --- | --- |
| codeSignsInOnce | httpapi/auth_test.go:TestEmailedCodeSignsInOnceAndKillsTheLinkToo | |
| wrongCodesLock | httpapi/auth_test.go:TestFiveWrongCodesLockTheLinkEvenForTheRightCode | |
| codeBoundToEmail | httpapi/auth_test.go:TestACodeOnlyWorksWithTheEmailItWasSentTo | |
| verifyValidation | httpapi/auth_test.go:TestVerifyNeedsATokenOrAnEmailAndCode | |

## AuthFlowTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| appleIsIdempotent | httpapi/auth_test.go:TestAppleSignInTwiceIsOneUserAndKeepsTheFirstName | |
| appleBadToken | httpapi/auth_test.go:TestAppleTokenThatDoesNotVerifyIs401 | |
| magicLinkSingleUse | httpapi/auth_test.go:TestMagicLinkSignsInOnceThenIsDead | |
| magicLinkExpiry | httpapi/auth_test.go:TestExpiredLinkIsRefusedAndTheTokenIsNeverStoredInClear | |
| magicLinkRateLimit | httpapi/auth_test.go:TestSignInEmailsAreRateLimitedPerAddress | |
| invalidEmail | httpapi/auth_test.go:TestInvalidEmailIs422NamingTheField | |
| signOut | httpapi/auth_test.go:TestSigningOutKillsThatSessionOnly | |
| accountDeleteLeavesNothing | httpapi/auth_test.go:TestAccountDeleteLeavesNoRowReferencingTheUser<br>httpapi/agent_parity_test.go:TestAccountDeleteLeavesNothingOfALibraryListsShelvesAndImports | extended: Swift's library item, list, shelf, import job rows |

## BadgeRuleTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| everyBadgeCovered | gamification/rules_test.go:TestEveryBadgeHasARuleTest | |
| tierBoundaries | gamification/rules_test.go:TestEachTierStartsExactlyAtItsThreshold | one subtest per badge id, as Swift's arguments |
| privateBadges | gamification/rules_test.go:TestOnlyNotesAndOwnedBadgesArePrivate | |
| ticks | gamification/rules_test.go:TestWriteFactsTicksComeFromTheInverse<br>library/facts_test.go:TestFactsTicksComeFromTheInverseNotTheRequest | ported: derive from op + inverse (collectFacts) |
| fields | gamification/rules_test.go:TestWriteFactsFieldsAndKinds<br>library/facts_test.go:TestFactsFinishingUnfinishingAndPagesImportsAndPlansDeriveNothing | ported: through collectFacts, imports and plans |

## BillingTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| verifies | billing/apple_test.go:TestTransactionVerifiesUpAnAppleShapedChainOnly | |
| root | billing/apple_test.go:TestAppleRootIsTheOneBundled | |
| purchase | billing/service_test.go:TestPurchaseLiftsTheCaptureLimit<br>httpapi/billing_test.go:TestEntitlementReportsPlusAndCaptures<br>httpapi/capture_test.go:TestCapturePlusLiftsTheMonthButKeepsThirtyADay | |
| notifications | billing/service_test.go:TestNotificationsRenewRefundAndExpire | |
| publicRoute | httpapi/billing_test.go:TestAppleReachesTheNotificationRouteWithoutASession | |
| fairUse | httpapi/capture_test.go:TestCapturePlusLiftsTheMonthButKeepsThirtyADay | |

## BoardStoreTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| feedPages | boards/store_test.go:TestStoreFeedIsNewestFirstAndPagesByBefore | |
| upvotes | boards/store_test.go:TestStoreUpvotesAreIdempotentAndCounted | |
| topWindow | boards/store_test.go:TestStoreTopOrdersByUpvotesInsideTheWindow | |
| deletedPosts | boards/store_test.go:TestStoreDeletedPostsVanish | |
| titlePostAndComments | boards/store_test.go:TestStoreTitlePostsCarryRatingAndSpoilerCommentsKeepDeletedRows | |
| accountDeletion | boards/store_test.go:TestStoreAccountDeletionLeavesNoBoardRows | |
| replySurvivesParentAccountDeletion | boards/store_test.go:TestStoreDeletingAnAccountKeepsOtherPeoplesRepliesToItsComments | |

## BoardTests+Comments.swift

| Swift test | Go test | note |
| --- | --- | --- |
| visibleToAudience | httpapi/board_comments_test.go:TestBoardCommentsAreVisibleToEveryoneWhoSeesThePost | |
| nestingStaysOneLevel | httpapi/board_comments_test.go:TestBoardReplyToAReplyHangsOffTheTopLevelComment | |
| blocksHide | httpapi/board_comments_test.go:TestBoardBlocksHideCommentsBothWays | |
| authorBlocksViewer | httpapi/board_comments_test.go:TestBoardAuthorWhoBlockedTheViewerIsTheMissing404AndOffTheFeed | |
| mentionAudience | httpapi/board_comments_test.go:TestBoardMentionsReachThePostsAudienceNotTheCommentersFriends | |
| blockedPostIs404 | httpapi/board_comments_test.go:TestBoardBlockedFriendsPostIsTheMissing404 | |
| deleting | httpapi/board_comments_test.go:TestBoardPostAuthorDeletesAnyCommentOthersOnlyTheirOwn | |
| deletedWithReplies | httpapi/board_comments_test.go:TestBoardDeletedCommentWithRepliesStaysAsAnEmptyRow | |
| deletedPost | httpapi/board_comments_test.go:TestBoardCommentingOnADeletedPostIsTheMissing404 | |
| aaruRecorded | httpapi/board_comments_test.go:TestBoardAaruInACommentIsRecordedNotAnswered | |
| validation | httpapi/board_comments_test.go:TestBoardCommentBodiesAreValidated | |
| filteredPageCursor | httpapi/board_comments_test.go:TestBoardAllFilteredCommentPageStillCarriesACursor | |
| hiddenCommentIsMissing | httpapi/board_comments_test.go:TestBoardHiddenCommentIsNotFoundToDeleteOrReplyTo | |

## BoardTests+Reviews.swift

| Swift test | Go test | note |
| --- | --- | --- |
| newTitle | httpapi/board_reviews_test.go:TestBoardReviewOfANewTitleAddsItAsWatchedWithTheRating | |
| keepsStatus | httpapi/board_reviews_test.go:TestBoardReviewOfATitleInProgressKeepsItsStatus | |
| noWrite | httpapi/board_reviews_test.go:TestBoardNoRatingMeansNoLibraryWriteABadRatingFails | |
| veil | httpapi/board_reviews_test.go:TestBoardSpoilersVeilFriendsWhoAreBehind | |

## BoardTests+Title.swift

| Swift test | Go test | note |
| --- | --- | --- |
| titlePosts | httpapi/board_title_test.go:TestBoardTitlePageListsFriendsPostsAboutItNewestFirst | |

## BoardTests+Upvotes.swift

| Swift test | Go test | note |
| --- | --- | --- |
| idempotent | httpapi/board_upvotes_test.go:TestBoardUpvoteTwiceCountsOnceRemovingTwiceIsFine | |
| hidden | httpapi/board_upvotes_test.go:TestBoardUpvotingAHiddenOrDeletedPostIsTheMissing404 | |
| upvotersHideBlocked | httpapi/board_upvotes_test.go:TestBoardUpvotersListHidesBlockedPeople | |

## BoardTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| visibility | httpapi/board_test.go:TestBoardFriendsSeePostsStrangersAndExFriendsGetTheMissing404 | |
| blocked | httpapi/board_test.go:TestBoardBlockedAuthorsPostsVanish | |
| validation | httpapi/board_test.go:TestBoardPostValidation | |
| authorOnly | httpapi/board_test.go:TestBoardOnlyTheAuthorEditsOrDeletes | |
| top | httpapi/board_test.go:TestBoardTopThisWeek | |

## CaptureTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `links` | capture/capture_test.go:TestCatalogLinksNameTheirTitleByIDAndExportSitesPointAtTheirCSV | |
| `reportedRows` | capture/capture_test.go:TestReportedTitlesAreDeduplicatedAndAnimeIsAShow | |
| `toolChoiceAndCost` | capture/capture_test.go:TestTheRequestForcesTheToolAndSendsNoSamplingParameters<br>capture/capture_parity_test.go:TestNoForcedToolSendsNoToolChoiceAndCostsRoundUp | extended: no tool_choice without one, micros rounded up |
| `pastedText` | httpapi/capture_test.go:TestCapturePastedTitlesPlanWriteNothingThenApplyAsOneUndoableAction | |
| `image` | httpapi/capture_test.go:TestCaptureImageGoesToTheModelAsOneBase64BlockWithItsType | |
| `nothingFound` | httpapi/capture_test.go:TestCaptureNothingFoundOrDeclinedFailsTheJobAndKeepsNothing | |
| `linkCaptures` | httpapi/capture_test.go:TestCaptureLinksPlanWithoutTheModelAndOtherLinksAreRefused | |
| `quota` | httpapi/capture_test.go:TestCaptureFreeAccountGetsThreeAMonthTheFourthIs402 | |
| `sweep` | httpapi/capture_test.go:TestCaptureSweepDeletesInputsLeftAnHour | |
| `month` | imports/stremio_capture_test.go:TestCaptureMonthAndDayBoundariesAreUTC | |

## CatalogAdapterTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| tmdbSearch | catalog/adapter_test.go:TestTMDBSearchCarriesTMDBAndIMDbIDs | |
| tmdbMulti | catalog/adapter_test.go:TestTMDBMultiKeepsFilmsAndShows | |
| tmdbBearer | catalog/adapter_test.go:TestTMDBReadTokenGoesInTheHeader | |
| tmdbEpisodes | catalog/adapter_test.go:TestTMDBEpisodesSpanEverySeason | |
| openLibrarySearch | catalog/adapter_test.go:TestOpenLibrarySearchNormalizesISBN | |
| aniListSearch | catalog/adapter_test.go:TestAniListSearchMarksAnime | |
| aniListReleaseDate | catalog/adapter_test.go:TestAniListReleaseDateOnlyWithTheDay | |
| aniListPlainText | catalog/adapter_test.go:TestAniListPlainText | |
| catalogDayRejectsRollover | catalog/adapter_test.go:TestParseDayRejectsRollover | |
| aniListEpisodes | catalog/adapter_test.go:TestAniListEpisodesFromTheSchedule | |
| genres | catalog/adapter_test.go:TestRecordsCarryGenreNames | |

## CatalogRefreshTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| pass | catalog/refresh_test.go:TestRefreshPass | |
| listMember | catalog/refresh_test.go:TestShowOnlyOnAListIsRefreshed | list row inserted in SQL, not via the route |
| airingWindow | catalog/refresh_test.go:TestAiringShowIsStaleAfterADay | |
| saveEpisodesUpserts | catalog/refresh_test.go:TestSaveEpisodesUpsertsAndNeverDeletes | |

## CatalogResolutionTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| concurrentResolution | catalog/resolution_test.go:TestConcurrentResolutionsMakeOneRow | |
| existingByIDs | catalog/resolution_test.go:TestKnownTitleIsFoundWithoutTheProvider | |
| titleAndYear | catalog/resolution_test.go:TestTitleAndYearResolveOnlyAnUnambiguousMatch | |
| isbnForms | catalog/resolution_test.go:TestISBN10And13ResolveToOneTitle | |
| animeMapping | catalog/resolution_test.go:TestMappedAnimeCoursResolveToOneShow | |
| episodeHydration | catalog/resolution_test.go:TestEpisodesHydrateOnceThenRefreshAfterTheWindow | |
| searchRoute | httpapi/catalog_test.go:TestSearchRoute | extended: no `release_date`, no `rating` on a hit |

## CatalogSearchAllTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| mixed | catalog/searchall_test.go:TestSearchAllMixesKindsExactFirst | |
| mappingDedupe | catalog/searchall_test.go:TestSearchAllDedupesOnlyThroughMappings | |
| animeStandIn | catalog/searchall_test.go:TestAnimeSearchStandsInWhileAniListIsDown | |
| partial | catalog/searchall_test.go:TestSearchAllAnswersWithWhatArrived | |
| ranking | catalog/searchall_test.go:TestRankedAlternatesAfterExactAndStopsAt40 | |
| route | httpapi/catalog_test.go:TestSearchRoute | extended: `type=show` answers `incomplete: false` |

## CATImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| list | `imports/parsers_test.go:TestCATList` |  |
| listLimits | `imports/parsers_test.go:TestCATListLimits` |  |
| calendarCollapses | `imports/parsers_test.go:TestCATCalendarCollapses` |  |
| calendarFolding | `imports/parsers_test.go:TestCATCalendarFolding` |  |
| calendarAirings | `imports/parsers_test.go:TestCATCalendarAirings` |  |
| detection | `imports/parsers_test.go:TestCATDetection` |  |
| links | `imports/parsers_test.go:TestCATLinks` |  |
| matching | `httpapi/imports_parsers_test.go:TestCATMatching` |  |
| airingTiebreak | `httpapi/imports_parsers_test.go:TestCATAiringTiebreak` |  |
| route | `httpapi/imports_parsers_test.go:TestCATRoute` |  |
| feed | `httpapi/imports_parsers_test.go:TestCATFeed` |  |
| realExportRows | `imports/parsers_test.go:TestCATRealExport` |  |

## ConcertSearchTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| search | concerts/ticketmaster_test.go:TestSearchSendsTheAreaOnlyWhenNear | |
| performerImages | concerts/ticketmaster_test.go:TestPerformersCarryARealPicture | |
| distance | concerts/ticketmaster_test.go:TestDistancesAreGreatCircleKilometres | |
| off | httpapi/concert_test.go:TestConcertsOffWithoutAProvider | |
| near | httpapi/concert_test.go:TestConcertSearchNearNeedsAPlace | |
| anywhere | httpapi/concert_test.go:TestConcertSearchAnywhereMeasuresOnTheServer | |
| performers | httpapi/concert_test.go:TestConcertPerformersForAName<br>httpapi/concert_test.go:TestConcertsOffWithoutAProvider | off half in the latter |
| byPerformer | httpapi/concert_test.go:TestConcertSearchByAPickedPerformer | |
| validation | httpapi/concert_test.go:TestConcertSearchValidation | |

## ConcertTests+ByID.swift

| Swift test | Go test | note |
| --- | --- | --- |
| eventByID | concerts/ticketmaster_test.go:TestAnEventByIDReadsOneEventAndA404IsNil | |
| concertByID | httpapi/concert_test.go:TestAConcertByIDIsCachedAndNeverAnError<br>httpapi/concert_test.go:TestConcertsOffWithoutAProvider | concerts-off half in the latter |

## ConcertTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| points | concerts/ticketmaster_test.go:TestPointsAreRoundedAndHashed | |
| near (ConcertAdapterTests) | concerts/ticketmaster_test.go:TestNearSendsTheCellRadiusAndPaging | |
| attractions | concerts/ticketmaster_test.go:TestPerformersKeepTheirMusicBrainzIDsLowercased | |
| budget | concerts/ticketmaster_test.go:TestASpentBudgetFailsFastAndResetsTheNextUTCDay | |
| redaction | middleware/concert_redaction_parity_test.go:TestTheConcertCitySearchIsNotLoggedWithItsQuery | ported |
| off | httpapi/concert_test.go:TestConcertsOffWithoutAProvider | |
| near (ConcertAPITests) | httpapi/concert_test.go:TestConcertsNearUseTheSavedCityOrAOneOffPoint | |
| cache | httpapi/concert_test.go:TestConcertsAreCachedPerAreaAndServedStaleOnFailure | |
| artists | httpapi/concert_test.go:TestYourArtistsOnTourMatchByMusicBrainzIDOnly | |

## DatabaseTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `migrationsRerun` | db/db_parity_test.go:TestMigrationsAreReRunnable | ported (goose up twice) |
| `waitForDatabaseReturns` | db/db_parity_test.go:TestWaitForGoesAheadOnceTheDatabaseAnswers | ported |
| `waitForDatabaseGivesUp` | db/db_parity_test.go:TestWaitForGivesUpWhenTheDatabaseNeverAnswers | ported |
| `identityIsUnique` | auth/store_parity_test.go:TestOneIdentityMapsToOneUser | ported |
| `externalIDsAreUnique` | catalog/store_parity_test.go:TestANonNullExternalIDIsUniqueAndNullsAreNot | ported |
| `titleRoundTrip` | catalog/store_parity_test.go:TestATitleRoundTrips | ported |
| `libraryItemIsUnique` | library/store_parity_test.go:TestASecondItemForTheSameTitleIsRejected | ported |
| `listRoundTrip` | library/store_parity_test.go:TestListsKeepMemberOrderAndArePrivate | ported |
| `importJobRoundTrip` | imports/store_parity_test.go:TestAnImportJobRoundTrips | ported |

## DiscoverSeasonTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| shifting | catalog/seasons_test.go:TestSeasonKeysCrossTheYearEnd | |
| days | catalog/seasons_test.go:TestSeasonDaysAreItsQuarter | table over the four seasons |
| aniList | catalog/seasons_test.go:TestAniListSeasonPage | |
| tmdb | catalog/seasons_test.go:TestTMDBSeasonFiltersByTheSeasonsDates | table over the three kinds |
| tmdbPastSeason | catalog/seasons_test.go:TestTMDBEndedSeasonKeepsAVoteFloor | |
| cache | catalog/seasons_test.go:TestSeasonCacheIsKeyedAndBounded | |
| unavailable | catalog/seasons_test.go:TestFailingSeasonReadsAsUnavailable | |
| route | catalog/seasons_test.go:TestSeasonMarksOwnedAndDropsPosterless<br>httpapi/catalog_test.go:TestDiscoverRoutes | marking in the service; title/from/until over HTTP |
| outOfRange | httpapi/catalog_test.go:TestDiscoverRoutes | the four queries, relative to the current year |
| nextYearAndSession | httpapi/catalog_test.go:TestDiscoverRoutes | |

## DiscoverTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| tmdbTrendingTV | catalog/discover_test.go:TestTMDBTVRowsLeaveOutAnimeAndTalkShows | |
| tmdbNewShows | catalog/discover_test.go:TestTMDBNewShowsWindow | |
| tmdbMovies | catalog/discover_test.go:TestTMDBMovieRowsKeepMovies | |
| aniListSeason | catalog/discover_test.go:TestAniListSeasonRow | |
| aniListManga | catalog/discover_test.go:TestAniListMangaRows | |
| rowKinds | catalog/discover_test.go:TestRowKinds | |
| openLibraryTrending | catalog/discover_test.go:TestOpenLibraryTrending | |
| season | catalog/discover_test.go:TestSeasonFollowsTheUTCQuarter | table over the seven instants |
| seasonTitle | catalog/discover_test.go:TestSeasonFollowsTheUTCQuarter | last assertion ("Fall 2026 anime") |
| cacheTTL | catalog/discover_test.go:TestCacheServesUntilTheTTL | |
| cacheCoalesces | catalog/discover_test.go:TestCacheCoalescesConcurrentCallers | |
| cacheFailure | catalog/discover_test.go:TestCacheServesStaleOnFailureAndBacksOff | |
| failingProvider | catalog/discover_test.go:TestFailingProviderDropsItsOwnRowOnly | |
| aniListOutageFallback | catalog/discover_test.go:TestAniListOutageFallsBackToTMDBAnime | |
| tmdbAnimeQuery | catalog/discover_test.go:TestTMDBAnimeStandInQuery | |
| route | catalog/discover_test.go:TestDiscoverMarksTheLibraryAndDropsPosterless<br>httpapi/catalog_test.go:TestDiscoverRoutes | extended: wire ids `tv_trending`/`movies_trending`, kinds `show`/`film` |
| needsSession | httpapi/catalog_test.go:TestDiscoverRoutes | |

## ExportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `json` | httpapi/export_test.go:TestExportJSON | |
| `csvRoundTrip` | httpapi/export_test.go:TestExportCSVRoundTripColumns<br>httpapi/export_test.go:TestExportCSVWatchedEpisodesAndAnime | extended: re-read by imports.DetectFormat + ParseGenericCSV |

## FavoritesTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `setReorderClear` | httpapi/favorite_test.go:TestAFavoriteKindIsSetReorderedAndCleared | |
| `validation` | httpapi/favorite_test.go:TestFavoritesValidation | |
| `animeKind` | httpapi/favorite_test.go:TestAnimeIsItsOwnFavoriteKind | |
| `friendsSeeThem` | httpapi/favorite_test.go:TestAFriendSeesYourFavoritesOnlyWhileYouShareYourLibrary | |
| `export` | httpapi/favorite_test.go:TestTheExportCarriesFavorites | |

## FriendTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| profile | httpapi/friend_test.go:TestAFriendsProfileShowsShelvesAndWhatYouShareNeverNotes | |
| privacy | httpapi/friend_test.go:TestOnlyFriendsSeeAProfileAndHidingTheLibraryLeavesTheName | |
| activity | httpapi/friend_test.go:TestActivityIsDatedTicksAndFinishesOneRowPerTitleAndDay | |

## GamificationTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| tickUndoRedo | gamification/service_test.go:TestTickEarnsOnceUntickTakesBackUndoRedoNetsOne<br>httpapi/gamification_parity_test.go:TestRouteTickEarnsOnceUntickTakesBackUndoRedoNetsOne | ported: through the tick and undo routes |
| seasonBonus | gamification/service_test.go:TestFullSeasonEarnsItsBonusAndUndoTakesAllBack<br>httpapi/gamification_parity_test.go:TestRouteFullSeasonEarnsItsBonusAndUndoTakesAllBack | ported: routes |
| dailyCap | gamification/service_test.go:TestDailyCapsHoldAndACappedAwardSpendsItsRoot<br>httpapi/gamification_parity_test.go:TestRouteDailyCapsHold | ported: routes |
| scrobbleOnce | gamification/service_test.go:TestTheSameScrobbleTwiceAwardsOnceWithTheBonus<br>httpapi/gamification_parity_test.go:TestScrobbleMarkWatchedAwardsOnceWithTheBonus | ported: through scrobble.Service.MarkWatched |
| importsEarnNothing | gamification/service_test.go:TestImportsAndPlansEarnNothingAndNoStreakDay<br>httpapi/gamification_parity_test.go:TestLibraryImportAndPlanWritesEarnNothingAndNoStreakDay | ported: through library.Store.Apply |
| friendPoints | gamification/service_test.go:TestFriendshipEarnsBothShortOneTakesBackRefriendingEarnsNothing<br>httpapi/gamification_parity_test.go:TestRouteFriendshipEarnsBothUnfriendTakesBackRefriendEarnsNothing | ported: invite, unfriend, re-invite routes |
| streakDayZone | gamification/service_test.go:TestStreakDayIsDatedInTheRequestZoneAndTheZoneIsKept<br>httpapi/gamification_parity_test.go:TestRouteStreakDayIsDatedInXTimezoneAndTheZoneIsKept | ported: X-Timezone header |
| liveBadge | gamification/service_test.go:TestALiveFinishEarnsUnseenBadgesOnce<br>httpapi/gamification_test.go:TestProgressBadgesAndSeen<br>httpapi/gamification_parity_test.go:TestRouteALiveFinishShowsAnUnseenBadgeOnce | ported: add route |
| undoTakesBadgeBack | gamification/service_test.go:TestUndoingTheActionThatEarnedATierTakesItBack<br>httpapi/gamification_parity_test.go:TestRouteUndoingTheActionThatEarnedATierTakesItBack | ported: undo route |
| backfill | gamification/service_test.go:TestTheFirstRunIsOneBackfillAndImportedHistoryCounts<br>httpapi/gamification_parity_test.go:TestRouteFirstRunIsOneBackfill | ported: unseen origin over the route |
| levels | gamification/rules_test.go:TestLevelsArePureFunctionsOfTotal | |
| weeks | gamification/rules_test.go:TestISOWeeks | |

## GenericImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| detection | `imports/parsers_test.go:TestDetection` |  |
| parse | `imports/parsers_test.go:TestGenericParse` |  |
| onHoldWords | `imports/parsers_test.go:TestGenericOnHoldWords` |  |
| ratingScales | `imports/parsers_test.go:TestGenericRatingScales` |  |
| autoUpload | `httpapi/imports_parsers_test.go:TestImportAutoGenericCSV` |  |

## GenreTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `storedAtHydration` | catalog/refresh_test.go:TestGenresAreStoredAtHydration | |
| `backfill` | catalog/refresh_test.go:TestGenreBackfill | |

## GoodreadsImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| unknownISBNFallsBackToTitleAndAuthor | `httpapi/imports_parsers_test.go:TestGoodreadsUnknownISBNFallsBackToTitleAndAuthor` |  |
| yearToleranceNeedsTheAuthor | `httpapi/imports_parsers_test.go:TestGoodreadsYearToleranceNeedsTheAuthor` |  |
| didNotFinishIsDropped | `httpapi/imports_parsers_test.go:TestGoodreadsDidNotFinishIsDropped` |  |
| reviewAndOwnedFillEmptyOnly | `httpapi/imports_parsers_test.go:TestGoodreadsReviewAndOwnedFillEmptyOnly` |  |
| ownedIsNeverCleared | `imports/parsers_test.go:TestOwnedIsNeverCleared` | merge decision on parser rows |

## GoogleSignInTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| validToken | auth/verifiers_test.go:TestGoogleValidTokenYieldsSubjectNameAndOnlyAVerifiedEmail | |
| rejections | auth/verifiers_test.go:TestGoogleRejectsWrongAudienceIssuerNonceOrExpiry | |
| signIn | httpapi/auth_test.go:TestGoogleSignInTwiceIsOneUserAndAForgedTokenIs401 | |
| unconfigured | httpapi/auth_test.go:TestGoogleWithoutClientIDsIs503 | |
| linking | httpapi/auth_test.go:TestLinkingAddsGoogleToTheAppleAccount | |
| conflict | httpapi/auth_test.go:TestAGoogleAccountOnAnotherUserIs409NeverAMerge | |

## GroupKindTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| spoilerGuard | httpapi/group_kinds_test.go:TestGroupTitleChannelSpoilerGuard | |
| shareProgress | httpapi/group_kinds_test.go:TestGroupTitleChannelShareProgress | |
| shelf | httpapi/group_kinds_test.go:TestGroupShelfChannel | |
| watchParty | httpapi/group_kinds_test.go:TestGroupWatchParty | |

## GroupPushTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| switches | httpapi/group_push_test.go:TestGroupPushSwitchesStartOffAndPutChangesOnlyWhatItSends | |
| mentions | httpapi/group_push_test.go:TestGroupPushMentionAlertsTheTaggedMemberOnceWithoutTheMessage | |
| invites | httpapi/group_push_test.go:TestGroupPushInviteAlertsTheFriendOnceOnlyWithInviteAlertsOn | |
| webPaths | httpapi/group_push_test.go:TestGroupPushWebAlertsOpenTheChannelOrTheGroupsPage | |

## GroupTests+Friendship.swift

| Swift test | Go test | note |
| --- | --- | --- |
| invitesEndWithFriendship | httpapi/group_test.go:TestGroupInvitesEndWithFriendship | |
| blockDropsOnlyThePairsInvites | httpapi/group_test.go:TestGroupBlockDropsOnlyThePairsInvites | |
| acceptRechecksFriendship | httpapi/group_test.go:TestGroupAcceptRechecksFriendship | |

## GroupTests+Nonce.swift

| Swift test | Go test | note |
| --- | --- | --- |
| nonceRetryStaysInItsChannel | httpapi/group_test.go:TestGroupNonceRetryStaysInItsChannel | |

## GroupTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| createAndHide | httpapi/group_test.go:TestGroupCreateNeedsHandleAndHidesFromOutsiders | |
| invites | httpapi/group_test.go:TestGroupInvitesAreFriendsOnly | |
| messages | httpapi/group_test.go:TestGroupMessagesPageRetryMentionAndUnread | |
| editDeleteBlock | httpapi/group_test.go:TestGroupEditDeleteAndBlockedAuthors | |
| rolesAndChannels | httpapi/group_test.go:TestGroupRolesChannelsAndOwnership | |
| accountDelete | httpapi/group_test.go:TestGroupAccountDeleteEmptiesMessagesAndHandsGroupsOn | |
| nonceIsTheAuthors | httpapi/group_test.go:TestGroupNonceIsTheAuthors | |
| pagination | httpapi/group_test.go:TestGroupPaginationWalksBackOnce | |
| mentionParsing | httpapi/group_test.go:TestGroupMentionParsing | |

## ImportFlowTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| goodreadsPlanApplyUndo | `httpapi/imports_core_test.go:TestImportGoodreadsPlanApplyUndo` |  |
| fillEmptyOnly | `httpapi/imports_core_test.go:TestImportFillsEmptyOnly` |  |
| expiredLeaseIsReclaimed | `httpapi/imports_core_test.go:TestImportExpiredLeaseIsReclaimed` |  |
| releasedJobIsClaimedAgain | `httpapi/imports_core_test.go:TestImportReleasedJobIsClaimedAgain` |  |
| failingJobFails | `httpapi/imports_core_test.go:TestImportFailingJobFails` |  |
| uploadLimits | `httpapi/imports_core_test.go:TestImportUploadLimits` |  |

## ImportMergeTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| sameSourceTwice | `httpapi/imports_merge_test.go:TestImportMergeSameSourceTwice` |  |
| wishlistMovesForward | `httpapi/imports_merge_test.go:TestImportMergeWishlistMovesForward` |  |
| neverBackwardNorOutOfDropped | `httpapi/imports_merge_test.go:TestImportMergeNeverBackwardNorOutOfDropped` |  |
| handSetStatusStays | `httpapi/imports_merge_test.go:TestImportMergeHandSetStatusStays` |  |
| undoRestoresTheFlag | `httpapi/imports_merge_test.go:TestImportMergeUndoRestoresTheFlag` |  |
| onHoldMovesSideways | `httpapi/imports_merge_test.go:TestImportMergeOnHoldMovesSideways` |  |
| malAfterTraktIsOneTitle | `httpapi/imports_merge_test.go:TestImportMergeMALAfterTraktIsOneTitle` |  |
| anilistSeasonsTickTheirSeason | `httpapi/imports_merge_test.go:TestImportMergeAniListSeasonsTickTheirSeason` |  |

## ImportOutageTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| plansAroundAniList | `httpapi/imports_core_test.go:TestImportPlansAroundAniListOutage` | extended: no per-entry AniList call at all |

## ImportParserTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| csvQuoting | `imports/parsers_test.go:TestCSVQuoting` |  |
| goodreads | `imports/parsers_test.go:TestGoodreadsParser` |  |
| goodreadsMore | `imports/parsers_test.go:TestGoodreadsMore` |  |
| goodreadsSeriesSuffix | `imports/parsers_test.go:TestGoodreadsSeriesSuffix` |  |
| imdb | `imports/parsers_test.go:TestIMDbParser` |  |
| letterboxd | `imports/parsers_test.go:TestLetterboxdParser` |  |
| wrongColumns | `imports/parsers_test.go:TestWrongColumns` |  |

## ImportResolveTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| afterApproval | `httpapi/imports_core_test.go:TestImportResolveAfterApproval` |  |
| beforeApproval | `httpapi/imports_core_test.go:TestImportResolveBeforeApproval` |  |
| mergesIntoExisting | `httpapi/imports_core_test.go:TestImportResolveMergesIntoExisting` |  |

## ImportSpeedTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| aniListBatches | `catalog/anilist_batch_test.go:TestAniListHydrateMALBatchesFiftyAtATime` | ported |
| malImportBatchedWithProgress | `httpapi/imports_core_test.go:TestImportMALBatchedWithProgress` |  |
| progressReports | `httpapi/imports_core_test.go:TestImportProgressReports` |  |

## InteractionTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `reactions` | httpapi/interaction_test.go:TestAFriendReactsOnceCanChangeOrClearAndYouSeeIt | |
| `recommendations` | httpapi/interaction_test.go:TestARecommendationReachesFriendsOnlyAndAddingIsOnePlanToWatchWrite | |

## InternalMetricsTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| count | httpapi/router_test.go:TestInternalMetricsNeedsSecret<br>httpapi/ops_parity_test.go:TestInternalMetricsTheRightBearerGetsTheNumberOfAccounts | ported: Cache-Control no-store, only `users` |
| rejected | httpapi/ops_parity_test.go:TestInternalMetricsNoWrongOrBareSecretIs401 | ported: all four arguments |
| sessionToken | httpapi/ops_parity_test.go:TestInternalMetricsASessionTokenIsNotTheSecret | ported |
| disabled | httpapi/ops_parity_test.go:TestInternalMetricsAnEmptySecretTurnsTheRouteOff | ported |

## InviteTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| redeem | httpapi/invite_test.go:TestAnInviteIsAOneUseLinkThatPreviewsSignedOutAndBefriends | |
| title | httpapi/invite_test.go:TestAnInvitesTitleLandsOnPlanToWatchOnlyWhenAsked | |
| deadEnds | httpapi/invite_test.go:TestRevokedExpiredAndBlockedInvitesReadAsInvalid | |
| cap | httpapi/invite_test.go:TestOpenInvitesAreCapped | |
| publicPaths | middleware/public_paths_test.go:TestOnlyABareInviteCodeIsPublic | ported |

## LeaderboardTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| optInAndBlocks | gamification/service_test.go:TestNobodyAppearsUntilTheyJoinAndBlocksHideBothWays<br>httpapi/gamification_parity_test.go:TestRouteLeaderboardNobodyAppearsUntilTheyJoinBlocksHideBothWays | ported: settings and block routes |
| boardPoints | gamification/service_test.go:TestFriendPointsStayOffTheBoardAndRanksFollowPoints<br>httpapi/gamification_test.go:TestLeaderboardRoute<br>httpapi/gamification_parity_test.go:TestRouteLeaderboardFriendPointsStayOffRanksFollowTheWeek | ported: routes |
| partialSettings | httpapi/gamification_parity_test.go:TestAnOlderAppsSettingsPutLeavesTheNewSwitchesAlone | ported |
| friendAchievements | gamification/service_test.go:TestFriendAchievementsHidePrivateBadgesAndRespectTheSwitch<br>httpapi/gamification_parity_test.go:TestRouteFriendsSeeLevelAndBadgesUnlessSwitchedOffNeverPrivate | ported: friend profile route |

## LibraryTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `addIsIdempotent` | httpapi/library_test.go:TestAddIsIdempotent | |
| `filtersAndPagination` | httpapi/library_test.go:TestFiltersAndPagination | |
| `patchRules` | httpapi/library_test.go:TestPatchRules | |
| `syncDeletes` | httpapi/library_test.go:TestSyncDeletes | |
| `journal` | httpapi/library_test.go:TestJournalOneRowPerWrite | |
| `patchNamesAction` | httpapi/library_test.go:TestPatchAndTickNameTheirAction | |
| `tickNamesAction` | httpapi/library_test.go:TestPatchAndTickNameTheirAction | |
| `undoSeason` | httpapi/library_test.go:TestUndoSeasonRestoresExactlyAndTwiceIsConflict | |
| `undoDelete` | httpapi/library_test.go:TestUndoDeleteRestoresProgress | |
| `tickRules` | httpapi/library_test.go:TestTickRules | |
| `watchedEpisodesOnSingleItem` | httpapi/library_test.go:TestWatchedEpisodesOnSingleItemOnly | |
| `seasonSkipsUnaired` | httpapi/library_test.go:TestSeasonSkipsUnaired | |
| `statusTransitions` | httpapi/library_test.go:TestStatusTransitions | |
| `bookProgress` | httpapi/library_test.go:TestBookProgress | |
| `statusLabels` | httpapi/library_test.go:TestStatusLabelsInTheJournal | |

## ListenBrainzRouteTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| singleListen | httpapi/listenbrainz_test.go:TestListenBrainzMusicTokenSendsAListenThatShowsInTheLogAndExport | |
| onlyMusicTokens | httpapi/listenbrainz_test.go:TestListenBrainzOnlyALiveMusicTokenGetsIn | |
| duplicates | httpapi/listenbrainz_test.go:TestListenBrainzTheSamePlayTwiceOrRespelledIsKeptOnce | |
| listenTypes | httpapi/listenbrainz_test.go:TestListenBrainzPlayingNowStoresNothingAndImportTakesUpTo1000 | |
| invalid | httpapi/listenbrainz_test.go:TestListenBrainzRefusesAListenWithoutArtistTrackOrAPlausibleTime | |
| validateToken | httpapi/listenbrainz_test.go:TestListenBrainzValidateTokenSaysWhetherAMusicTokenWorks | |
| pages | httpapi/listenbrainz_test.go:TestListensPagesGoBackInTimeWithNext | |
| top | httpapi/listenbrainz_test.go:TestListensTopCountsAcrossSpellings | |
| musicSetup | httpapi/listenbrainz_test.go:TestMusicTokenIsNamedForItsScrobblerAndComesWithItsSteps | |

## ListenImportParserTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| spotifyHistory | imports/listen_parsers_test.go:TestListenSpotifyHistory | |
| spotifyRefusals | imports/listen_parsers_test.go:TestListenSpotifyRefusals | |
| takeoutMusicOnly | imports/listen_parsers_test.go:TestListenTakeoutMusicOnly | |
| takeoutOtherLanguage | imports/listen_parsers_test.go:TestListenTakeoutOtherLanguage | |
| lastFMPage | imports/listen_parsers_test.go:TestListenLastFMPage | |
| lastFMReader | imports/listen_parsers_test.go:TestListenLastFMReader | |
| listenBrainzReader | imports/listen_parsers_test.go:TestListenBrainzReader | |
| listenBrainzMapping | imports/listen_parsers_test.go:TestListenBrainzMapping | |

## ListenImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| spotifyPlanApplyUndo | httpapi/listen_imports_test.go:TestListenImportSpotifyPlanApplyUndo | |
| refusals | httpapi/listen_imports_test.go:TestListenImportRefusals | |
| accountImport | httpapi/listen_imports_test.go:TestListenImportAccount | |
| libraryImportUndo | httpapi/listen_imports_test.go:TestListenImportUndoRefusesLibraryImport | |
| bigApply | httpapi/listen_imports_test.go:TestListenImportBigApply | |

## ListenResolverTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| queries | catalog/recording_parity_test.go:TestRecordingSearchAsksBySentIDElseISRCElseArtistAndTitle | ported |
| exactOnly | catalog/recording_parity_test.go:TestRecordingMatchIsExactOnlyAndTheAlbumIsTheOneNamed | ported |
| sentID | catalog/recording_parity_test.go:TestRecordingMatchTrustsTheSentIDWhateverTheSpelling | ported |
| byline | catalog/recording_parity_test.go:TestRecordingMatchAJoinedCreditMatchesTheWholeByline | ported |
| resolves | httpapi/listen_resolver_test.go:TestListenResolverAsksEachTrackOnceAndItsListensGainTheAlbum | |
| missesAndSentIDs | httpapi/listen_resolver_test.go:TestListenResolverKeepsAMissForAMonthAndNeverOverwritesSentIDs | |
| linksCatalogAlbum | httpapi/listen_resolver_test.go:TestListenResolverLinksAnAlbumAlreadyInTheCatalogByItsAaruID | |

## ListenStatsTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| statsMusic | httpapi/stats_test.go:TestStatsMusic | |
| topRows | httpapi/listen_resolver_test.go:TestListensTopRowsCarryCoversLinkAlbumsAndNarrowToOneArtist | |

## ListShelfTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `listsAreScoped` | httpapi/list_test.go:TestListsAreScoped | |
| `membership` | httpapi/list_test.go:TestListMembership | |
| `richRows` | httpapi/list_test.go:TestListRowsCarryEntryAndAiring | |
| `shelfIsAQuery` | httpapi/list_test.go:TestAShelfIsAQuery | |
| `shelfMatchesFilter` | httpapi/list_test.go:TestAShelfMatchesItsFilter | |

## MALPullTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| readsChangesSinceTheCursor | httpapi/mal_test.go:TestMALReadsChangesSinceTheCursor | |
| echoesAndBackwardMovesAreIgnored | httpapi/mal_test.go:TestMALEchoesAndBackwardMovesAreIgnored | |
| onHoldReadBack | httpapi/mal_test.go:TestMALOnHoldReadBack | |
| onHoldBackfill | db/migrations/onhold_parity_test.go:TestAdoptionNeedsAddOnHoldsBackfillToHaveRun<br>db/migrations/onhold_parity_test.go:TestAFreshBaselineTakesOnHold<br>db/migrations/baseline_test.go:TestAdoptingASwiftDatabaseNeedsTheBaselinesMigrations | N/A: runs Fluent's one-time `AddOnHold.backfill`; Go has no backfill since a Swift DB is adopted only after AddOnHold ran and an empty DB has nothing to fill. Ported tests prove both |
| removalsAreListedNotApplied | httpapi/mal_test.go:TestMALRemovalsAreListedNotApplied | |
| revokedWhileReading | httpapi/mal_test.go:TestMALRevokedWhileReading | |
| rowsAndStates | mal/rules_test.go:TestRowsAndStates | |

## MALTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| connectWithPlainPKCE | httpapi/mal_test.go:TestMALConnectWithPlainPKCE | |
| unavailableWithoutClientID | httpapi/mal_test.go:TestMALUnavailableWithoutClientID | |
| pushesPerSeason | httpapi/mal_test.go:TestMALPushesPerSeason | |
| airingSeasonOfFinishedShow | httpapi/mal_test.go:TestMALAiringSeasonOfFinishedShow | |
| onlyLaterWritesAndNoSplitCours | httpapi/mal_test.go:TestMALOnlyLaterWritesAndNoSplitCours | |
| pushesOnHold | httpapi/mal_test.go:TestMALPushesOnHold | |
| revokedToken | httpapi/mal_test.go:TestMALRevokedTokenStopsPushing | |
| rules | mal/rules_test.go:TestTargetAndStateRules | |

## MangaImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| malMangaParser | `imports/parsers_test.go:TestMALMangaParser` |  |
| malMangaFlow | `httpapi/imports_parsers_test.go:TestMALMangaFlow` |  |
| mangaProgressOnlyMovesForward | `imports/parsers_test.go:TestMangaProgressOnlyMovesForward` | merge decision on parser rows |

## MangaTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| search (AniListMangaAdapterTests) | catalog/manga_test.go:TestMangaSearchCreditsTheAuthors | |
| animeStaysAnime | catalog/manga_test.go:TestAnimeSearchAsksNoCredits | |
| malBatchType | catalog/manga_test.go:TestMALBatchesAskForTheListsType | |
| add | catalog/manga_test.go:TestMangaResolvesWithAuthorAndCounts<br>httpapi/music_sports_parity_test.go:TestMangaAddedByAniListReadsPlanReadingRead | ported (route: isAnime, volumeCount) |
| progress | httpapi/library_test.go:TestMangaProgressAndLabels | |
| labelsAndFilter | httpapi/music_sports_parity_test.go:TestMangaAddedByAniListReadsPlanReadingRead | ported (full journal sequence) |
| malIDsArePerList | catalog/manga_test.go:TestAnimeAndMangaWithOneMALNumberAreTwoTitles | |
| search (MangaLibraryTests) | catalog/manga_test.go:TestMangaSearchSaysWhenAniListIsDown | |

## MCPTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| handshake | httpapi/mcp_test.go:TestMCPHandshake | |
| authentication | httpapi/mcp_test.go:TestMCPOnlyALiveMCPTokenGetsIn<br>httpapi/scrobble_test.go:TestScrobbleRouteBrowserTokenOnlyScrobblesAndIsListedOnItsOwnSurface | extended: a browser scrobble token gets 401 on /v1/mcp |
| reads | httpapi/mcp_test.go:TestMCPReadsComeBackAsV1DTOs | |
| writes | httpapi/mcp_test.go:TestMCPTapSizedWritesApplyBiggerOnesWaitReadOnlyNeverWrites | |
| planImport | httpapi/mcp_test.go:TestMCPPlanImportQueuesForReviewAndNeedsTheImportsScope<br>httpapi/agent_parity_test.go:TestMCPPlanImportQueuesAJobTheUserSees | extended: real import service, job listed in /v1/imports |

## MetricsTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| render | metrics/metrics_test.go:TestCountersGaugeAndHistogramRenderInTheTextFormat | ported; labels render in name order (Prometheus client), same names and values |
| escaping | metrics/metrics_test.go:TestALabelValueCannotBreakOutOfItsQuotes | ported |
| group | metrics/metrics_test.go:TestRoutesGroupByTheirFirstSegmentAfterV1 | ported: all five arguments |
| routeTemplate | middleware/metrics_test.go:TestTheRouteLabelIsTheMatchedTemplateNeverThePath | ported |
| listener | metrics/metrics_test.go:TestTheMetricsHandlerServesTheTextFormat<br>app/internal_mux_test.go:TestInternalMuxServesProfilesWhenEnabled | ported |
| off | app/internal_mux_test.go:TestMetricsPortZeroTurnsTheListenerOff | ported (listener construction moved to newMetricsServer) |
| notOnTheAPI | httpapi/ops_parity_test.go:TestTheAPIPortHasNoMetrics | ported |

## MusicTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| search (MusicBrainzAdapterTests) | catalog/music_test.go:TestMusicBrainzSearch | |
| hydrate | catalog/music_test.go:TestMusicBrainzHydrate | |
| tracks | catalog/music_test.go:TestMusicBrainzTracksFromTheEarliestRelease | |
| addAndDetail | catalog/music_test.go:TestAlbumDetailCarriesArtistGenresAndTracks<br>httpapi/catalog_test.go:TestAlbumDetailRoute | service + wire DTO |
| tracksDown | catalog/music_test.go:TestAlbumDetailWithoutMusicBrainz | |
| labelsAndFilter | httpapi/library_test.go:TestAlbumLabels | |
| search (AlbumLibraryTests) | catalog/music_test.go:TestAlbumSearchIsMusicBrainzAlone | |
| newAlbums | catalog/music_test.go:TestListenBrainzNewAlbums | |
| upcoming | catalog/music_test.go:TestListenBrainzComingSoon | |
| otherList | catalog/music_test.go:TestListenBrainzOtherListIsNotFound | |

## NetflixImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| titles | `imports/parsers_test.go:TestNetflixTitles` |  |
| dates | `imports/parsers_test.go:TestNetflixDates` |  |
| rows | `imports/parsers_test.go:TestNetflixRows` |  |
| format | `imports/parsers_test.go:TestNetflixFormat`<br>`imports/parsers_test.go:TestDetection` |  |
| episodeNames | `imports/parsers_test.go:TestNetflixEpisodeNames` |  |
| matching | `httpapi/imports_parsers_test.go:TestNetflixMatching` |  |

## NowPlayingTests+LateToken.swift

| Swift test | Go test | note |
| --- | --- | --- |
| lateToken | httpapi/now_playing_test.go:TestNowPlayingLateTokenHearsThePauseThenTheStopItMissed | |

## NowPlayingTests+Plays.swift

| Swift test | Go test | note |
| --- | --- | --- |
| order | httpapi/now_playing_plays_test.go:TestLiveSetOrderEpisodesAndVideosFirstThenTracksThreeAtMostNoDoubleVideo | |
| differs | httpapi/now_playing_plays_test.go:TestLiveActivityChangesOnlyWhenWhatItShowsChanges | |
| trackBesideEpisode | httpapi/now_playing_plays_test.go:TestNowPlayingASongJoinsTheEpisodeIsReplacedByTheNextAndLeavesWhenItEnds | |
| videoAndTrackAlone | httpapi/now_playing_plays_test.go:TestNowPlayingAVideoAloneStartsPausesAndEndsTheActivity | |
| sweepClaims | httpapi/now_playing_plays_test.go:TestLiveActivitySweepClaimsADueUserOnce | |
| videoBody | httpapi/now_playing_plays_test.go:TestVideoScrobbleBodyIsYouTubesIDANameAndADuration | |

## NowPlayingTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| liveness | httpapi/now_playing_test.go:TestNowPlayingLiveness | |
| bingeWithStops | httpapi/now_playing_test.go:TestNowPlayingEachStopPast80TicksItsOwnEpisodeOnce | |
| nextEpisodeWithoutStop | httpapi/now_playing_test.go:TestNowPlayingNextEpisodeWithoutAStopClosesTheLastTickingOnlyPast80 | |
| endpoint | httpapi/now_playing_test.go:TestNowPlayingEndpointShowsTheOpenEpisodeAndNothingOnceItStops | |
| liveActivity | httpapi/now_playing_test.go:TestNowPlayingLiveActivityStartUpdateWatchedLingerAndSweepEnd | one more push: the route catches a new token up (Swift's harness route had no notifier) |
| registration | httpapi/now_playing_test.go:TestNowPlayingLiveActivityTokenRegistrationRefusesBadInput | |

## OAuthTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| discovery | httpapi/oauth_test.go:TestOAuthDiscoveryNamesAarusEndpoints<br>httpapi/mcp_test.go:TestMCPOnlyALiveMCPTokenGetsIn | challenge header asserted in the MCP test |
| registration | httpapi/oauth_test.go:TestOAuthRegistrationTakesHTTPSOrLoopbackAndAuthorizeNeverRedirectsElsewhere | |
| flow | httpapi/oauth_test.go:TestOAuthFullFlowRefreshRotationAndReuseDetection | |
| revocation | httpapi/oauth_test.go:TestOAuthReusedCodeRevokesWhatItIssuedAndSettingsRevokeStopsRefresh<br>httpapi/agent_token_test.go:TestClaudeConnectsOverOAuthNeverWithAPastedToken | |

## OnAirGuideTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| tmdbOnAir | catalog/onair_test.go:TestTMDBOnAir | |
| grouping | catalog/onair_test.go:TestGroupOnAir | |
| streamsOn | catalog/onair_test.go:TestStreamsOnLeavesOutTheChannelAndResellers | |
| tvmazeNextAirTime | catalog/onair_test.go:TestTVmazeNextAirTime | |
| refineTolerance | catalog/onair_test.go:TestRefineOnAirTolerance | |
| publishesBeforeRefining | catalog/onair_test.go:TestOnAirPublishesDatesBeforeExactTimes | |
| failureIsEmpty | catalog/onair_test.go:TestOnAirFailureIsAnEmptyGuide | |
| route | catalog/onair_test.go:TestOnAirMarksOwnedAndListsTheRegionsServices<br>httpapi/onair_parity_test.go:TestOnAirRouteGroupsByChannelAndListsServices | ported the HTTP half: wire shape, `streamsOn` absent without data, 422 region |

## PageCountTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `pageCounts` | httpapi/library_test.go:TestBookProgress<br>catalog/refresh_test.go:TestPageCountBackfill | add carries the count; refresher fills a missing one |

## PlanTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `approve` | httpapi/plan_test.go:TestPlanWritesNothingUntilApprovedThenOneUndoableAction | |
| `stale` | httpapi/plan_test.go:TestPlanWhoseLibraryMovedIsStale | |
| `denyAndExpire` | httpapi/plan_test.go:TestPlanDenyExpiryAndRevokedTokens | |
| `onlyTheOwner` | httpapi/plan_test.go:TestPlanOnlyTheSignedInOwnerDecides | |

## ProfileTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `split` | auth/store_parity_test.go:TestANameSplitsAtTheFirstSpace | ported |
| `names` | httpapi/profile_test.go:TestFirstAndLastNameAreSavedJoinedAndKeptWhenLeftOut | |
| `olderApps` | httpapi/profile_test.go:TestAnOlderAppsDisplayNameIsNoChangeWhenItMatches | |
| `avatarUpload` | httpapi/profile_test.go:TestAnAvatarIsAJPEGUnder1MB | |
| `avatarReach` | httpapi/profile_test.go:TestAnAvatarShowsToAnyoneSignedInNeverSignedOutBlockedOrOnTheInvitePreview | extended: group member avatar |
| `email` | httpapi/profile_test.go:TestFriendsSeeTheEmailOnlyWhileShared | |
| `exportAndDelete` | httpapi/profile_test.go:TestTheExportCarriesNamesAndAvatarAndDeleteTakesTheAvatar | |

## ProvenanceTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `agentWrite` | httpapi/library_test.go:TestAnAgentWriteNamesItsTokenAndUndoes | |

## ProviderClientTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| retriesRateLimits | provider/client_test.go:TestRetriesRateLimitsWithBackoff | |
| givesUp | provider/client_test.go:TestGivesUpAfterThreeAttemptsAndNever404 | |
| honoursRetryAfter | provider/client_test.go:TestHonoursRetryAfter | |
| cancellationPropagates | provider/client_test.go:TestCancellationPropagates | |
| aniListDisabled | catalog/anilist_classify_parity_test.go:TestAniListDisabledIsAnOutageAskedOnce | ported |

## PushTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| registration | httpapi/push_test.go:TestDevicesRegisterPerUserAndEnvironment | |
| setting | httpapi/push_test.go:TestNotificationSwitchesStartOffAndChangeOneByOne | |
| announcesOnce | push/airing_test.go:TestAiringAnnouncedOnce | extended: titleId/libraryItemId uppercase (Go fix) |
| optedOut | push/airing_test.go:TestAiringNotSentWithoutOptIn | |

## RealtimeTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| hubFanOut | httpapi/realtime_test.go:TestRealtimeHubDeliversOnlyToRecipientsAndDropsAFailingSocket | |
| tickets | httpapi/realtime_test.go:TestRealtimeTicketWorksOnceAndOnlyForAMinute | |
| groupEvents | httpapi/realtime_test.go:TestRealtimeGroupWritesReachMembersFlaggedForBlockers | |
| socket | httpapi/realtime_test.go:TestRealtimeSocketUpgradesWithBearerOrTicketAndRefusesForeignOrigins | |
| commands | httpapi/realtime_test.go:TestRealtimeOnlyAWellFormedFrameIsACommand | |
| foreignOrigin | httpapi/realtime_test.go:TestRealtimeForeignOriginTicketIsRefusedAndStaysUnspent | |

## ScheduleTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `week` | httpapi/schedule_test.go:TestCalendarWeek | |
| `pending` | httpapi/schedule_test.go:TestCalendarPendingShows<br>httpapi/watching_parity_test.go:TestTheCalendarWaitsForTheRefresherAndLoadsNothing | extended: the read loads nothing; the refresher clears the wait |
| `artworkAndAirTime` | httpapi/schedule_test.go:TestCalendarArtworkAndAirTime | |
| `upNext` | httpapi/schedule_test.go:TestUpNextAdvances | |
| `finaleFlag` | httpapi/schedule_test.go:TestUpNextFinaleFlag | |
| `counts` | httpapi/schedule_test.go:TestUpNextCounts | |
| `unfinished` | httpapi/schedule_test.go:TestUpNextUnfinished | |
| `onHoldIsHidden` | httpapi/schedule_test.go:TestOnHoldLeavesUpNextAndCalendar | |

## ScrobbleRouteTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| watchedEpisode | httpapi/scrobble_test.go:TestScrobbleRouteWatchedEpisodeIsJournaledAsTheExtension | |
| byName | httpapi/scrobble_test.go:TestScrobbleRouteMatchesAnEpisodeByNameAndLeavesAnAmbiguousFilmUnmatched | |
| auth | httpapi/scrobble_test.go:TestScrobbleRouteOnlyALiveBrowserTokenGetsIn | |
| tokenScope | httpapi/scrobble_test.go:TestScrobbleRouteBrowserTokenOnlyScrobblesAndIsListedOnItsOwnSurface | extended: /v1/mcp refuses the browser token (401) |
| validation | httpapi/scrobble_test.go:TestScrobbleRouteRefusesABodyThatIsNotAScrobble | |

## ScrobbleTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| watchedEpisode | httpapi/scrobble_test.go:TestScrobbleWatchedEpisodeTicksOnceAndARepeatStopIsANoOp | |
| shortOrUnknown | httpapi/scrobble_test.go:TestScrobbleStopShortOrWithUnknownDurationTicksNothing | |
| durationFromEarlierReport | httpapi/scrobble_test.go:TestScrobbleDurationLearnedAtStartCountsWhenStopReportsZero | |
| absentShow | httpapi/scrobble_test.go:TestScrobbleAbsentShowIsAddedInProgressAndJournaledAsTheAgent | |
| movieAndUnmatched | httpapi/scrobble_test.go:TestScrobbleMovieIsFinishedAndAnUnknownIDIsUnmatched | |

## ShareStoreTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| roundTrip | httpapi/share_test.go:TestEachShareTargetRoundTripsAndATakenCodeConflicts | |
| dedupeByNote | shares/store_test.go:TestTheSameSenderTargetAndNoteFindTheSameLink | ported (route-level note dedupe also in httpapi/share_test.go:TestTheSameTargetAndNoteReuseOneLink) |
| accountDeleteKeepsLink | httpapi/share_test.go:TestDeletingTheSendersAccountKeepsTheLinkAndDropsTheirNameAndNote | |

## ShareTests+Limits.swift

| Swift test | Go test | note |
| --- | --- | --- |
| titleNeedsNoProvider | httpapi/share_test.go:TestASharedShowOpensFromTheCatalogRowAloneWhileTheCatalogIsDown | |
| unknownEventsRefused | httpapi/share_test.go:TestAnEventTheProviderDoesNotKnowCannotBeShared | |
| providerBudgets | httpapi/share_limits_test.go:TestShareLookupsStopAtTheirOwnBudget | ported |
| emojiNote | httpapi/share_test.go:TestBadShareTargetsAndNotesAreRefused | the 👍🏽×100 case |

## ShareTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| createAndOpenSignedOut | httpapi/share_test.go:TestAShareIsAReusableLinkThatShowsItsTitleSignedOut | |
| url | httpapi/share_test.go:TestTheShareURLIsTheWebPage | |
| dedupeByNote | httpapi/share_test.go:TestTheSameTargetAndNoteReuseOneLink | |
| friendSeesSender | httpapi/share_test.go:TestAFriendSeesWhoSentItAndTheNoteAStrangerDoesNot | |
| senderSeesSelf | httpapi/share_test.go:TestAFriendSeesWhoSentItAndTheNoteAStrangerDoesNot | last assertions |
| blockHidesSender | httpapi/share_test.go:TestABlockShowsTheContentAndHidesTheSender | |
| viewerItem | httpapi/share_test.go:TestASignedInOpenerWhoHasTheTitleGetsTheirItemAndStatus | |
| sportEventResult | httpapi/share_test.go:TestASharedMatchShowsItsResultToAnyone | |
| concertUnavailable | httpapi/share_test.go:TestASharedConcertShowsOrSaysUnavailable | |
| badTargets | httpapi/share_test.go:TestBadShareTargetsAndNotesAreRefused | |
| unknownCode | httpapi/share_test.go:TestAnUnknownShareCodeIsOne404 | |
| rateLimits | httpapi/share_test.go:TestMakingLinksIsLimitedPerUser | |
| publicPath | middleware/public_paths_test.go:TestOnlyAShareCodesPreviewPathIsPublic | ported |

## ShowWatchedTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `endedShow` | httpapi/library_test.go:TestEndedShowWatchedInOneUndatedAction<br>httpapi/stats_test.go:TestProfileStatsWholeShowWatched | stats half in stats_test |
| `seasonUndated` | httpapi/library_test.go:TestSeasonMarkIsUndated | |
| `runningShow` | httpapi/library_test.go:TestRunningShowWatchedStaysInProgressAndAgainIsANoOp | |
| `patchFinished` | httpapi/library_test.go:TestPatchFinishedOnAShowIsTheWholeShow | |
| `addAsWatched` | httpapi/library_test.go:TestAddAShowAsWatched | |
| `profile` | httpapi/stats_test.go:TestProfileStats | |

## SocialTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| handles | httpapi/social_test.go:TestHandlesAreValidatedLowercasedUniqueAndShowOnMe | |
| friendFlow | httpapi/social_test.go:TestFriendRequestAcceptUnfriendAndWithdraw | |
| blocks | httpapi/social_test.go:TestABlockEndsTheFriendshipAndIsA404BothWays | |
| reportsAndDelete | httpapi/social_test.go:TestReportsForRealUsersOnlyAndAccountDeleteRemovesTheGraph | |
| rateLimits | httpapi/social_test.go:TestLookupsAndRequestsAreLimitedPerHourSeparately | |
| rateLimitsSpareFriends | httpapi/social_test.go:TestAFriendOrYourselfCostsNoLookup | |
| handleChangeLimit | httpapi/social_test.go:TestHandleChangesAreLimitedAndResavingIsFree | |

## SportsAdapterTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| search | sports/thesportsdb_test.go:TestSearchSendsTheKeyAsAHeaderAndAnUnderscoredSlug | |
| schedule | sports/thesportsdb_test.go:TestSchedulesReadScoresTimestampsAndCards | |
| v1Calls | sports/thesportsdb_test.go:TestV1CallsCarryTheKeyInThePath | |
| live | sports/thesportsdb_test.go:TestLivescoresBecomeEventsWithTheClock | |
| statuses | sports/thesportsdb_test.go:TestStatusesMapToFive | |

## SportsTests+Public.swift

| Swift test | Go test | note |
| --- | --- | --- |
| publicEventNeedsNoUser | httpapi/sports_test.go:TestAPublicSportEventNeedsNoUserAndSharesTheCache | |
| publicEventOff | httpapi/sports_test.go:TestSportsOffWithoutAProvider | last assertion: ErrSportsOff |

## SportsTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| off | httpapi/sports_test.go:TestSportsOffWithoutAProvider | |
| follows | httpapi/sports_test.go:TestFollowingKeepsASnapshot | |
| limit | httpapi/sports_test.go:TestAtTheLimitANewFollowIsRefused | |
| favorites | httpapi/sports_test.go:TestSportFavoritesLiveNextAndLast | |
| pending | httpapi/sports_test.go:TestSlowSportFavoritesArePendingThenReady | |
| schedule | httpapi/sports_test.go:TestSportScheduleOneLocalDay | |
| event | httpapi/sports_test.go:TestSportEventWhereToWatch | |
| isolation | httpapi/music_sports_parity_test.go:TestSportsStayInSportsAndTheExportCarriesThem | ported |
| search | httpapi/sports_test.go:TestSportSearchAllThreeKindsInOrder | |

## StatsTests+Rolling.swift

| Swift test | Go test | note |
| --- | --- | --- |
| rollingPeriod | stats/digest_test.go:TestRollingPeriod | |
| rollingValidation | stats/digest_test.go:TestRollingValidation | |
| rolling | httpapi/stats_test.go:TestStatsRolling<br>httpapi/stats_parity_test.go:TestRouteStatsRollingWindowsLeaveImportsOut | ported: route-seeded |

## StatsTests+YearReview.swift

| Swift test | Go test | note |
| --- | --- | --- |
| topGenres | stats/digest_test.go:TestTopGenres | |
| biggestDay | stats/digest_test.go:TestBiggestDay | |
| persona | stats/digest_test.go:TestPersona | |
| genresInStats | httpapi/stats_test.go:TestStatsGenres<br>httpapi/stats_parity_test.go:TestRouteStatsStoredGenresReachTheStats | ported: route-seeded |

## StatsTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| buckets | stats/digest_test.go:TestBuckets | |
| longestRun | stats/digest_test.go:TestLongestRun | |
| digest | stats/digest_test.go:TestDigest | |
| mostEpisodes | stats/digest_test.go:TestMostEpisodes | |
| byKind | stats/digest_test.go:TestByKind | |
| albums | stats/digest_test.go:TestAlbums | |
| ratingBins | stats/digest_test.go:TestRatingBins | |
| allTimePeriod | stats/digest_test.go:TestAllTimePeriod | |
| spanValidation | stats/digest_test.go:TestSpanValidation | |
| validation | stats/digest_test.go:TestValidation | |
| stats | httpapi/stats_test.go:TestStatsRealTicksAndDatedFinishes<br>httpapi/stats_parity_test.go:TestRouteStatsRealTicksAndDatedFinishesCountImportsAndOthersNever | ported: seeded through the routes and an import write, as Swift |
| timeZones | httpapi/stats_test.go:TestStatsTimeZones<br>httpapi/stats_parity_test.go:TestRouteStatsEdgesAreTheUsersTimeZone | ported: route-seeded |
| allTime | httpapi/stats_test.go:TestStatsAllTime<br>httpapi/stats_parity_test.go:TestRouteStatsAllTimeEqualsTheYearsSummed | ported: route-seeded |
| restoreIsNotActivity | httpapi/stats_test.go:TestStatsRestoredTicksAreNotActivity<br>httpapi/stats_parity_test.go:TestRouteUndoingADeleteRestoresTicksWithoutMakingThemTodaysWatching | ported: tick, delete, undo through the routes |

## StremioEpisodeMapTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| sameDay | stremio/episodemap_test.go:TestMatchIsTheTMDBEpisodeOutTheSameDayAFewHoursEitherWay<br>stremioapi/stremioapi_test.go:TestAnEpisodeMatchesTheTMDBEpisodeOutTheSameDay | |
| doubleBill | stremio/episodemap_test.go:TestMatchPairsTwoEpisodesOneDayInOrderOnlyWhenBothListsHaveTwo<br>stremioapi/stremioapi_test.go:TestTwoEpisodesOutOneDayPairUpInOrder | |
| unplaced | stremio/episodemap_test.go:TestMatchPlacesNothingWithoutAReleaseDayOrAnEpisodeThatDay<br>stremioapi/stremioapi_test.go:TestNoReleaseDayOrNoEpisodeThatDayPlacesNothing | |
| translated | httpapi/stremio_map_test.go:TestStremioMapTicksTheTMDBEpisodesStremiosNumbersName | |
| cinemetaDown | httpapi/stremio_map_test.go:TestStremioMapWithCinemetaDownTicksNothingRatherThanTheWrongEpisode | |
| duplicateEntry | httpapi/stremio_map_test.go:TestStremioMapFindsANearEmptyDuplicateSeriesByItsTVDBID | |

## StremioImportTests+TVDB.swift

| Swift test | Go test | note |
| --- | --- | --- |
| tvdbShow | `httpapi/stremio_import_test.go:TestStremioSeriesTMDBListsApartIsImportedOntoTheTVDBShow` |  |

## StremioImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| bitfield | `stremioapi/stremioapi_test.go:TestWatchedBitfieldMarksTheRightEpisodesAndLeavesSpecialsOut` |  |
| mapper | `imports/stremio_capture_test.go:TestStremioItemsMapToRows` |  |
| linkFlow | `httpapi/stremio_import_test.go:TestStremioPendingThenApprovedReadsOnceLogsOutAndImportsTicks` |  |
| expiry | `httpapi/stremio_import_test.go:TestStremioExpiredCodeIs410AndForgottenSomeoneElsesIsNotFound` |  |
| routes | `httpapi/stremio_import_test.go:TestStremioOverHTTPStartReturnsTheCodeAndAPendingPollIs204` |  |

## StremioTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| paths | httpapi/stremio_test.go:TestStremioPathsParseWithEncodedIDsAndExtraSegments | |
| manifest | httpapi/stremio_test.go:TestStremioManifestDeclaresNoStreamAndCORSIsOnEveryAnswer | |
| catalogs | httpapi/stremio_test.go:TestStremioCatalogsContinueWishlistSkipMetaAndEmptyOnceRevoked | |
| playerEvents | httpapi/stremio_test.go:TestStremioPlayerStopTicksTheEpisodeByIMDbAndAaruIDs | |
| libraryEvents | httpapi/stremio_test.go:TestStremioLibraryEventsWatchedIsOneActionAndWritesNeedOptIn | |
| scopes | httpapi/stremio_test.go:TestStremioTokenWithoutScrobbleWriteIsRefusedPlayerEvents | |

## TelemetryTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| dsn | telemetry/telemetry_test.go:TestDSNBecomesTheEnvelopeEndpoint | all five arguments |
| serverError | telemetry/telemetry_test.go:TestServerErrorReachesSentryWithNothingFromTheRequest | |
| postHog | telemetry/telemetry_test.go:TestPostHogGetsTheEventTheAccountAndOnlyTheAllowedProperties | |
| unconfigured | app/internal_mux_test.go:TestNothingIsSentWithoutConfiguration<br>telemetry/telemetry_test.go:TestCaptureGoesToTheInstalledSinkOnly | ported: makeSentry/makePostHog(nil) |
| events | httpapi/ops_parity_test.go:TestCreatingAListCountsTheListAndTheLibraryAction | ported |

## TitlePreviewTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `notInLibrary` | httpapi/library_test.go:TestResolvingIsNotAdding | |
| `inLibrary` | httpapi/library_test.go:TestResolvingIsNotAdding | |
| `unknown` | httpapi/library_test.go:TestResolvingIsNotAdding | |

## TonightTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `momentum` | tonight/service_test.go:TestMomentumAndNearnessOrderShows | |
| `feedback` | tonight/service_test.go:TestFeedbackHidesForTheDayAndWeighs | |
| `booksAndFilms` | tonight/service_test.go:TestBooksAndFilms | |
| `airing` | tonight/service_test.go:TestAiringShowsLocalTime | |
| `durations` | tonight/service_test.go:TestDurations | |
| `roundTrip` | httpapi/tonight_test.go:TestTonightFeedbackRoundTrip | |
| `clearFeedback` | httpapi/tonight_test.go:TestTonightUndo | |
| `empty` | httpapi/tonight_test.go:TestTonightEmpty | |

## TraktTests+API.swift

| Swift test | Go test | note |
| --- | --- | --- |
| readsEveryPage | `trakt/importer_test.go:TestImporterReadsEveryPage` |  |
| hostsAndHeaders | `httpapi/trakt_test.go:TestTraktHostsAndHeaders` |  |
| refreshesOnce | `httpapi/trakt_test.go:TestTraktRefreshesOnce` |  |
| refusedRefresh | `httpapi/trakt_test.go:TestTraktRefusedRefreshFailsAndDisconnects` |  |
| accountLimit | `httpapi/trakt_test.go:TestTraktAccountLimit` |  |
| disconnectRevokes | `httpapi/trakt_test.go:TestTraktDisconnectRevokes` |  |

## TraktTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| connectWithPKCE | `httpapi/trakt_test.go:TestTraktConnectWithPKCE` |  |
| refreshesExpiringToken | `httpapi/trakt_test.go:TestTraktRefreshesExpiringToken` |  |
| traktImport | `httpapi/trakt_test.go:TestTraktImportPlansThenApplies` |  |
| revokedToken | `httpapi/trakt_test.go:TestTraktRevokedTokenFailsAndDisconnects` |  |
| notConfigured | `httpapi/trakt_test.go:TestTraktNotConfigured` |  |

## TVmazeAirTimesTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| refines | catalog/tvmaze_test.go:TestTVmazeRefinesAirTimes | |
| ignoresMismatchedNumbering | catalog/tvmaze_test.go:TestTVmazeIgnoresMismatchedNumbering | |
| unknownShow | catalog/tvmaze_test.go:TestTVmazeUnknownShowIsUnchanged | |

## TVTimeImportTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| layouts | `imports/parsers_test.go:TestTVTimeLayouts`<br>`imports/parsers_test.go:TestDetection` | zip + generic detection in TestDetection |
| dates | `imports/parsers_test.go:TestTVTimeDates` |  |
| seriesEpisodes | `imports/parsers_test.go:TestTVTimeSeriesEpisodes` |  |
| series | `imports/parsers_test.go:TestTVTimeSeries` |  |
| movies | `imports/parsers_test.go:TestTVTimeMovies` |  |
| trackingV2 | `imports/parsers_test.go:TestTVTimeTrackingV2` |  |
| trackingV1 | `imports/parsers_test.go:TestTVTimeTrackingV1` |  |
| followedAndSeen | `imports/parsers_test.go:TestTVTimeFollowedAndSeen` |  |
| matching | `httpapi/imports_parsers_test.go:TestTVTimeMatching` |  |
| movieMatching | `httpapi/imports_parsers_test.go:TestTVTimeMovieMatching` |  |

## VideoListenTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| heard | httpapi/video_listen_test.go:TestVideoListenHeardIsHalfOrFourMinutesOfAVideoOf30sOrMore | |
| videoIDs | httpapi/video_listen_test.go:TestVideoIDIsReadFromEveryYouTubeWatchLinkAndNothingElse | |
| oneListen | httpapi/video_listen_test.go:TestVideoListenIsOneListenHoweverOftenItReportsAndEarnsPoints | |
| sameVideo | httpapi/video_listen_test.go:TestVideoListenAndAScrobblersListenOfTheSameVideoAreOnePlay | |

## WatchingTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| `importedAnime` | httpapi/watching_parity_test.go:TestAnImportedAnimeIsBacklogUntilTheFirstLiveTick | ported (through a real import) |
| `notBacklog` | httpapi/watching_parity_test.go:TestByHandImportedShowsAndLaterImportsAreNotBacklog | ported (through a real import) |
| `watching` | httpapi/schedule_test.go:TestWatching | |

## WebPushTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| offWithoutKey | httpapi/push_test.go:TestWebPushKeyIs503WithoutVAPID | |
| subscribe | httpapi/push_test.go:TestBrowserSubscribes | |
| fanOut | push/airing_test.go:TestAiringReachesABrowserOnlyUser | extended: libraryItemId uppercase (Go fix) |
| endpoints | push/webpush_test.go:TestEndpointAllowlist | |

## WebVisitorAddressTests.swift

| Swift test | Go test | note |
| --- | --- | --- |
| visitorNeedsSecret | middleware/auth_test.go:TestVisitorCountsOnlyWithTheWorkersSecret | |
| magicLinkLimitPerVisitor | httpapi/auth_test.go:TestSignInEmailLimitIsPerVisitorBehindTheWorker | |
