#import "PLPythonRuntime.h"
#define PY_SSIZE_T_CLEAN
#include <Python/Python.h>

@interface PLPythonRuntime ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSCondition *inputCondition;
@property (atomic) BOOL cancellationRequested;
@property (nonatomic, copy, nullable) NSString *answer;
@property (nonatomic, strong) NSMutableString *output;
@property (nonatomic) NSTimeInterval lastOutputTime;
@property (nonatomic, copy, nullable) NSString *initializationError;
@end

static PLPythonRuntime *runtimeInstance;

static PyObject *nativeWrite(PyObject *self, PyObject *args) {
    const char *bytes;
    Py_ssize_t size;
    if (!PyArg_ParseTuple(args, "s#", &bytes, &size)) return NULL;
    NSString *value = [[NSString alloc] initWithBytes:bytes length:(NSUInteger)size encoding:NSUTF8StringEncoding];
    [runtimeInstance.output appendString:value ?: @""];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - runtimeInstance.lastOutputTime > .05) {
        runtimeInstance.lastOutputTime = now;
        NSString *snapshot = [runtimeInstance.output copy];
        dispatch_async(dispatch_get_main_queue(), ^{ if (runtimeInstance.outputHandler) runtimeInstance.outputHandler(snapshot); });
    }
    Py_RETURN_NONE;
}

static PyObject *nativeRead(PyObject *self, PyObject *args) {
    const char *prompt;
    if (!PyArg_ParseTuple(args, "s", &prompt)) return NULL;
    NSString *text = [NSString stringWithUTF8String:prompt] ?: @"";
    [runtimeInstance.inputCondition lock];
    runtimeInstance.answer = nil;
    NSString *snapshot = [runtimeInstance.output copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (runtimeInstance.outputHandler) runtimeInstance.outputHandler(snapshot);
        if (runtimeInstance.inputHandler) runtimeInstance.inputHandler(text);
    });
    Py_BEGIN_ALLOW_THREADS
    while (!runtimeInstance.answer && !runtimeInstance.cancellationRequested) {
        [runtimeInstance.inputCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    }
    Py_END_ALLOW_THREADS
    NSString *answer = runtimeInstance.answer;
    BOOL stopped = runtimeInstance.cancellationRequested;
    [runtimeInstance.inputCondition unlock];
    if (stopped || !answer) Py_RETURN_NONE;
    NSData *data = [answer dataUsingEncoding:NSUTF8StringEncoding];
    return PyUnicode_DecodeUTF8(data.bytes, (Py_ssize_t)data.length, "strict");
}

static PyObject *nativeCancelled(PyObject *self, PyObject *args) {
    return PyBool_FromLong(runtimeInstance.cancellationRequested);
}

static PyMethodDef nativeMethods[] = {
    {"write", nativeWrite, METH_VARARGS, NULL},
    {"read", nativeRead, METH_VARARGS, NULL},
    {"cancelled", nativeCancelled, METH_NOARGS, NULL},
    {NULL, NULL, 0, NULL}
};
static struct PyModuleDef nativeModule = {PyModuleDef_HEAD_INIT, "_learnpy_native", NULL, -1, nativeMethods};
static PyObject *PyInit_learnpy_native(void) { return PyModule_Create(&nativeModule); }

@implementation PLPythonRuntime
+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ runtimeInstance = [[self alloc] init]; });
    return runtimeInstance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.wjc0104.pylearn.python", DISPATCH_QUEUE_SERIAL);
        _inputCondition = [[NSCondition alloc] init];
        _output = [NSMutableString string];
    }
    return self;
}

- (BOOL)initializeInterpreter {
    if (Py_IsInitialized()) return YES;
    NSString *resources = NSBundle.mainBundle.resourcePath;
    NSString *home = [resources stringByAppendingPathComponent:@"python"];
    PyImport_AppendInittab("_learnpy_native", PyInit_learnpy_native);
    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode = 0;
    config.install_signal_handlers = 0;
    config.use_environment = 0;
    PyStatus status = PyConfig_SetBytesString(&config, &config.home, home.UTF8String);
    if (!PyStatus_Exception(status)) {
        config.module_search_paths_set = 1;
        NSArray<NSString *> *paths = @[
            [home stringByAppendingPathComponent:@"lib/python3.13"],
            [home stringByAppendingPathComponent:@"lib/python3.13/lib-dynload"],
            resources
        ];
        for (NSString *path in paths) {
            wchar_t *wide = Py_DecodeLocale(path.UTF8String, NULL);
            if (!wide) { self.initializationError = @"无法解析 Python 资源路径。"; break; }
            status = PyWideStringList_Append(&config.module_search_paths, wide);
            PyMem_RawFree(wide);
            if (PyStatus_Exception(status)) break;
        }
        if (!PyStatus_Exception(status) && !self.initializationError) status = Py_InitializeFromConfig(&config);
    }
    if (PyStatus_Exception(status)) self.initializationError = [NSString stringWithUTF8String:status.err_msg ?: "Python 初始化失败"];
    PyConfig_Clear(&config);
    if (self.initializationError) return NO;
    // The serial queue can use different OS threads between requests.
    PyEval_SaveThread();
    return YES;
}

- (void)performRequest:(NSString *)json completion:(void (^)(NSString *))completion {
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    BOOL isRun = [payload[@"action"] isEqual:@"run"];
    if (isRun) self.cancellationRequested = NO;
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            NSString *response = nil;
            if ([self initializeInterpreter]) {
                PyGILState_STATE gil = PyGILState_Ensure();
                if (isRun) { [self.output setString:@""]; self.lastOutputTime = 0; }
                PyObject *module = PyImport_ImportModule("runtime");
                PyObject *function = module ? PyObject_GetAttrString(module, "request") : NULL;
                PyObject *result = function ? PyObject_CallFunction(function, "s", json.UTF8String) : NULL;
                if (result) {
                    const char *value = PyUnicode_AsUTF8(result);
                    if (value) response = [NSString stringWithUTF8String:value];
                }
                if (PyErr_Occurred()) PyErr_Print();
                Py_XDECREF(result); Py_XDECREF(function); Py_XDECREF(module);
                PyGILState_Release(gil);
            }
            if (!response) {
                NSDictionary *error = @{@"status":@"error", @"error":@{@"kind":@"RuntimeError", @"message":self.initializationError ?: @"Python 运行层调用失败。", @"hint":@"请检查安装包中的 Python 运行资源。"}};
                NSData *data = [NSJSONSerialization dataWithJSONObject:error options:0 error:nil];
                response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            }
            NSString *snapshot = [self.output copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isRun && self.outputHandler) self.outputHandler(snapshot);
                completion(response);
            });
        }
    });
}

- (void)submitInput:(NSString *)value {
    [self.inputCondition lock];
    self.answer = value;
    [self.inputCondition signal];
    [self.inputCondition unlock];
}

- (void)cancel {
    self.cancellationRequested = YES;
    [self.inputCondition lock];
    [self.inputCondition signal];
    [self.inputCondition unlock];
}
@end
