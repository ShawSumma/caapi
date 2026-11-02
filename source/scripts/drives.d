module scripts.drives;

import client.drive : DriveAction, DriveKey, NamedDrive, Toggle, captureTo, framesOf, holdKey, logging, moveBy, releaseKey, summaryOf, tapKey, watching;

enum uint LOAD_FRAMES = 300;
enum uint STILL_FRAMES = 30;
enum double TURN_COUNTS = 300;
enum uint TURN_FRAMES = 60;
enum uint FLY_FRAMES = 180;

immutable DriveAction[] FLY = [
    framesOf(LOAD_FRAMES),
    summaryOf("loading"),
    tapKey(DriveKey.n),
    holdKey(DriveKey.w),
    logging(Toggle.on),
    framesOf(FLY_FRAMES),
    logging(Toggle.off),
    releaseKey(DriveKey.w),
    summaryOf("flying forward in noclip"),
];

immutable DriveAction[] TURN = [
    framesOf(LOAD_FRAMES),
    summaryOf("loading"),
    watching(Toggle.on),
    captureTo("screenshots/drivestill1.png"),
    framesOf(STILL_FRAMES),
    summaryOf("standing still"),
    moveBy(TURN_COUNTS, 0, TURN_FRAMES),
    summaryOf("turning by mouse"),
    captureTo("screenshots/driveturned1.png"),
    framesOf(1),
    tapKey(DriveKey.n),
    holdKey(DriveKey.w),
    framesOf(FLY_FRAMES),
    releaseKey(DriveKey.w),
    summaryOf("flying forward in noclip"),
    captureTo("screenshots/driveflown1.png"),
    framesOf(1),
];

immutable NamedDrive[] DRIVES = [
    NamedDrive("fly", FLY),
    NamedDrive("turn", TURN),
];
