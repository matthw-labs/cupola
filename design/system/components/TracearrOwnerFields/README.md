# TracearrOwnerFields

The owner's access, inside a Tracearr connection's own settings: the optional second credential that lets Cupola Acknowledge and Dismiss a violation. The public key always reads; this one only writes the two things the public API has no route for.

Rendered from `lib/features/tracearr/presentation/tracearr_owner_fields.dart` (`TracearrOwnerFields`) by `test/design_catalog/tracearr_owner_fields_catalog_test.dart`; the steps are `TracearrOwnerSignInFlow` (`tracearr_owner_sign_in_flow.dart`), the words are `TracearrOwnerNotice` (`tracearr_owner_notice.dart`), the buttons and the password field are the Seerr sign-in's (`SeerrSignInPrimary`, `SeerrSignInBusy`, `seerrSignInAction`, `SeerrSignInPasswordField`), and the notices are `NoticeLine`.

## Where it is drawn

Under the key field of a saved Tracearr connection that works, headed by `SettingsSectionLabel` *Owner access*. Never for a connection that is not saved or set up: the sign-in goes through the saved connection's own route (`connectionReachProvider`), so an address, a gateway's access and a pin are the connection's, never the saved address. Moving the connection's address to another host forgets the session, so the bearer never travels there unasked; adding or changing the address away does not, being a second route to the same Tracearr that the key already travels.

## States

- **Nobody signed in**: `bodySmall` in `onSurfaceVariant`, *Cupola reads with the key. The owner can also acknowledge and dismiss violations.*, then the ink primary **Sign in as the owner** (44pt).
- **Asking** and **Signing in**: the busy primary with a 16px spinner, not tappable.
- **The form**: *Sign in as the owner* (`titleSmall` at 600), **Name or email**, **Password** (obscured, with a show toggle), the ink primary **Sign in**, **Continue with Plex** only where Tracearr offers Plex, **Cancel**, and under them *Your password goes only to <host>. Cupola doesn't keep it.* The password leaves the field the moment it is sent.
- **Plex**: *Finish signing in with Plex* · *Approve Tracearr on the Plex page, then come back here.* · **Open the Plex page again** · **Cancel**. Tracearr makes the PIN and checks it; Cupola only opens `app.plex.tv` (a page at any other host is refused), so plex.tv never hears from the device and never receives a gateway's headers. Asked once a second while the page is on screen, for at most 15 minutes (`The Plex sign-in timed out`, blue, **Start again**).
- **Signed in**: *Signed in as Anna* (`titleSmall` at 600) over *Tracearr · <host>* (`bodySmall`), and the outlined **Sign out** (44pt) behind a neutral confirmation. The session lasts 30 days past its last use and is read once a day of use to keep it.
- **The session ended**: a blue `NoticeLine`, *Signed out of Tracearr* · *Sign in as the owner again to acknowledge and dismiss.*, and the ink primary **Sign in again**, which goes back to the way the owner came in. Never amber, never red.
- **A notice a step ends with**: amber for a refused password (*That name or email and password didn't work*), blue for a step that is the person's (*Only the owner can acknowledge* for a member's or an administrator's account), and for single sign-on, which Cupola cannot finish, *This Tracearr signs in with single sign-on, which Cupola can't use.* · *Acknowledge it in Tracearr.*, said once, with no button that cannot be kept. A Tracearr with no owner yet is *This Tracearr isn't set up yet*, and nothing here ever creates one.

## Do / don't

- Do keep the token in secure storage and nowhere else, and the password in the field until it is sent.
- Do read the role of `/auth/me` before keeping a session, and end a refused one at Tracearr.
- Don't offer a sign-in Cupola cannot finish; say so once, with the remedy.
- Don't paint an ended session as a fault.
