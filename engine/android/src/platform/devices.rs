//! O que só o Java sabe: as entradas de áudio conectadas (`AudioManager.getDevices`) e se o app tem
//! a permissão de gravar. Pela JNI, sem código Kotlin: a máquina virtual vem do `JNI_OnLoad` (se o
//! app carregar a biblioteca pelo `System.loadLibrary`) ou do `JNI_GetCreatedJavaVMs` (público no
//! Android 12+), e o contexto do `ActivityThread.currentApplication()`. Sem máquina virtual as
//! funções respondem "não sei" (`None`, lista vazia) e o app segue com a entrada padrão.

use std::ffi::c_void;
use std::sync::atomic::{AtomicPtr, Ordering};

use jni::objects::{JObject, JObjectArray, JString, JValue};
use jni::{JNIEnv, JavaVM, sys};

static VM: AtomicPtr<sys::JavaVM> = AtomicPtr::new(std::ptr::null_mut());

/// Chamado pela máquina virtual quando o app carrega a biblioteca pelo Java.
#[unsafe(no_mangle)]
pub extern "system" fn JNI_OnLoad(vm: *mut sys::JavaVM, _reserved: *mut c_void) -> sys::jint {
    VM.store(vm, Ordering::Release);
    sys::JNI_VERSION_1_6
}

fn created_vm() -> Option<*mut sys::JavaVM> {
    type GetCreated = unsafe extern "system" fn(*mut *mut sys::JavaVM, sys::jsize, *mut sys::jsize) -> sys::jint;
    for lib in [c"libnativehelper.so", c"libart.so"] {
        // SAFETY: dlopen/dlsym com nomes fixos; a função tem a assinatura da especificação JNI
        unsafe {
            let h = libc::dlopen(lib.as_ptr(), libc::RTLD_NOW);
            if h.is_null() {
                continue;
            }
            let f = libc::dlsym(h, c"JNI_GetCreatedJavaVMs".as_ptr());
            if f.is_null() {
                continue;
            }
            let f: GetCreated = std::mem::transmute::<*mut c_void, GetCreated>(f);
            let (mut vm, mut n) = (std::ptr::null_mut(), 0);
            if f(&mut vm, 1, &mut n) == sys::JNI_OK && n > 0 && !vm.is_null() {
                return Some(vm);
            }
        }
    }
    None
}

fn vm() -> Option<JavaVM> {
    let mut p = VM.load(Ordering::Acquire);
    if p.is_null() {
        p = created_vm()?;
        VM.store(p, Ordering::Release);
    }
    // SAFETY: ponteiro da própria máquina virtual, que vive o processo inteiro
    unsafe { JavaVM::from_raw(p) }.ok()
}

/// Roda `f` com a JNI na thread atual; exceção Java ou erro viram `None`.
fn with_env<R>(f: impl FnOnce(&mut JNIEnv) -> jni::errors::Result<R>) -> Option<R> {
    let vm = vm()?;
    let mut env = vm.attach_current_thread_permanently().ok()?;
    let r = env.with_local_frame(64, |env| f(env));
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
    r.ok()
}

fn application<'a>(env: &mut JNIEnv<'a>) -> jni::errors::Result<JObject<'a>> {
    env.call_static_method("android/app/ActivityThread", "currentApplication", "()Landroid/app/Application;", &[])?.l()
}

/// O app tem a permissão RECORD_AUDIO? `None` = não deu para saber.
pub fn record_permission() -> Option<bool> {
    with_env(|env| {
        let app = application(env)?;
        let name = env.new_string("android.permission.RECORD_AUDIO")?;
        let r = env.call_method(&app, "checkSelfPermission", "(Ljava/lang/String;)I", &[JValue::Object(&name)])?.i()?;
        // PackageManager.PERMISSION_GRANTED
        Ok(r == 0)
    })
}

/// Uma entrada conectada.
struct Device {
    id: i32,
    kind: i32,
    product: String,
    address: String,
}

fn inputs(env: &mut JNIEnv) -> jni::errors::Result<Vec<Device>> {
    let app = application(env)?;
    let name = env.new_string("audio")?;
    let am = env.call_method(&app, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;", &[JValue::Object(&name)])?.l()?;
    // AudioManager.GET_DEVICES_INPUTS
    let arr = JObjectArray::from(env.call_method(&am, "getDevices", "(I)[Landroid/media/AudioDeviceInfo;", &[JValue::Int(1)])?.l()?);
    let n = env.get_array_length(&arr)?;
    let mut out = Vec::with_capacity(n.max(0) as usize);
    for i in 0..n {
        let d = env.get_object_array_element(&arr, i)?;
        let id = env.call_method(&d, "getId", "()I", &[])?.i()?;
        let kind = env.call_method(&d, "getType", "()I", &[])?.i()?;
        let pn = env.call_method(&d, "getProductName", "()Ljava/lang/CharSequence;", &[])?.l()?;
        let product = if pn.is_null() {
            String::new()
        } else {
            let s = JString::from(env.call_method(&pn, "toString", "()Ljava/lang/String;", &[])?.l()?);
            env.get_string(&s)?.into()
        };
        // getAddress é da API 28; antes dela a chamada lança e o endereço fica vazio
        let address = match env.call_method(&d, "getAddress", "()Ljava/lang/String;", &[]).and_then(|v| v.l()) {
            Ok(a) if !a.is_null() => env.get_string(&JString::from(a)).map(String::from).unwrap_or_default(),
            Ok(_) => String::new(),
            Err(_) => {
                let _ = env.exception_clear();
                String::new()
            }
        };
        env.delete_local_ref(d)?;
        out.push(Device { id, kind, product, address });
    }
    Ok(out)
}

/// A entrada `id` está conectada? `None` = não deu para saber.
pub fn input_exists(id: i32) -> Option<bool> {
    with_env(inputs).map(|list| list.iter().any(|d| d.id == id))
}

/// Tipos de `AudioDeviceInfo` que servem de entrada para gravar música, com o nome em português.
/// Os de telefonia, rádio, captura interna e eco ficam de fora.
fn label(kind: i32, product: &str) -> Option<String> {
    let named = |what: &str| if product.is_empty() { what.to_owned() } else { format!("{what}: {product}") };
    Some(match kind {
        15 => "Microfone do aparelho".to_owned(),
        3 => "Microfone do fone com fio".to_owned(),
        11 | 12 => named("USB"),
        22 => named("Fone USB"),
        7 => named("Bluetooth"),
        26 => named("Bluetooth LE"),
        5 | 19 => "Entrada de linha".to_owned(),
        6 => "Entrada digital".to_owned(),
        9 | 10 | 29 => "HDMI".to_owned(),
        13 | 31 => named("Dock"),
        _ => return None,
    })
}

fn address_label(a: &str) -> &str {
    match a {
        "bottom" => "inferior",
        "top" => "superior",
        "back" => "traseiro",
        "front" => "frontal",
        other => other,
    }
}

/// `[["id", "nome"], ...]`, sem repetir nomes (vários microfones do aparelho ganham a posição).
pub fn input_devices_json() -> String {
    let list = with_env(inputs).unwrap_or_default();
    let mut named: Vec<(String, String)> = Vec::new();
    for d in &list {
        let Some(name) = label(d.kind, &d.product) else { continue };
        let twins = list.iter().filter(|o| label(o.kind, &o.product).as_deref() == Some(name.as_str())).count();
        let name = if twins > 1 && !d.address.is_empty() { format!("{name} ({})", address_label(&d.address)) } else { name };
        named.push((d.id.to_string(), name));
    }
    serde_json::to_string(&named).unwrap_or_else(|_| "[]".to_owned())
}
