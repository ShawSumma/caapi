#ifdef __APPLE__

#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>

#else

#define VK_USE_PLATFORM_XLIB_KHR
#include <vulkan/vulkan.h>
#include <X11/XKBlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XI2.h>

typedef struct {
    int deviceid;
    int mask_len;
    unsigned char *mask;
} XIEventMask;

typedef struct {
    int mask_len;
    unsigned char *mask;
    double *values;
} XIValuatorState;

typedef struct {
    int type;
    unsigned long serial;
    Bool send_event;
    Display *display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    int sourceid;
    int detail;
    int flags;
    XIValuatorState valuators;
    double *raw_values;
} XIRawEvent;

typedef struct {
    int type;
    int sourceid;
} XIAnyClassInfo;

typedef struct {
    int type;
    int sourceid;
    int number;
    Atom label;
    double min;
    double max;
    double value;
    int resolution;
    int mode;
} XIValuatorClassInfo;

typedef struct {
    int deviceid;
    char *name;
    int use;
    int attachment;
    Bool enabled;
    int num_classes;
    XIAnyClassInfo **classes;
} XIDeviceInfo;

typedef struct {
    int type;
    unsigned long serial;
    Bool send_event;
    Display *display;
    int extension;
    int evtype;
    Time time;
    int deviceid;
    int sourceid;
    int reason;
    int num_classes;
    XIAnyClassInfo **classes;
} XIDeviceChangedEvent;

extern Status XIQueryVersion(Display *dpy, int *major_version_inout, int *minor_version_inout);
extern int XISelectEvents(Display *dpy, Window win, XIEventMask *masks, int num_masks);
extern XIDeviceInfo *XIQueryDevice(Display *dpy, int deviceid, int *ndevices_return);
extern void XIFreeDeviceInfo(XIDeviceInfo *info);

#endif
