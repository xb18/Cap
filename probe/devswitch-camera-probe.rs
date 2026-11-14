//! Probe only (not shipped): Studio recording that switches camera mid-way,
//! the way the GPUI app does, then rides out the new camera disappearing and
//! reopens it on the same feed when it is listed again.

use cap_recording::{
    feeds::camera::{self, CameraFeed, DeviceOrModelID},
    screen_capture::ScreenCaptureTarget,
    *,
};
use kameo::{Actor as _, actor::ActorRef};
use scap_targets::Display;
use std::{sync::Arc, time::Duration};

fn find(label: &str) -> Option<String> {
    cap_camera::list_cameras()
        .find(|camera| camera.display_name() == label)
        .map(|camera| camera.device_id().to_string())
}

async fn open(label: &str) -> (ActorRef<CameraFeed>, Arc<camera::CameraFeedLock>, String) {
    let id = find(label).unwrap_or_else(|| panic!("camera {label} not listed"));
    let feed = CameraFeed::spawn(CameraFeed::default());
    feed.ask(camera::SetInput {
        id: DeviceOrModelID::DeviceID(id.clone()),
        settings: None,
    })
    .await
    .expect("set camera")
    .await
    .expect("open camera");
    let lock = feed.ask(camera::Lock).await.expect("lock camera");
    println!(
        "PROBE opened {label} {}x{}",
        lock.video_info().width,
        lock.video_info().height
    );
    (feed, Arc::new(lock), id)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter("warn,cap_recording=info")
        .init();
    let out = std::path::PathBuf::from(std::env::args().nth(1).expect("out dir"));
    let _ = std::fs::remove_dir_all(&out);
    std::fs::create_dir_all(&out).unwrap();
    let (_a_feed, a_lock, _) = open("Cap Test Camera A").await;
    let handle = studio_recording::Actor::builder(
        out.clone(),
        ScreenCaptureTarget::Display {
            id: Display::primary().id(),
        },
    )
    .with_camera_feed(a_lock.clone())
    .build()
    .await
    .unwrap();
    drop(a_lock);

    tokio::time::sleep(Duration::from_secs(12)).await;
    let started = std::time::Instant::now();
    handle.pause().await.unwrap();
    handle.set_camera_feed(None).await.unwrap();
    let (b_feed, b_lock, b_id) = open("Cap Test Camera B").await;
    handle.set_camera_feed(Some(b_lock.clone())).await.unwrap();
    handle.resume().await.unwrap();
    println!(
        "PROBE switched camera gap_ms={:.0}",
        started.elapsed().as_secs_f64() * 1000.0
    );

    let deadline = std::time::Instant::now() + Duration::from_secs(36);
    let mut gone = false;
    while std::time::Instant::now() < deadline {
        tokio::time::sleep(Duration::from_secs(1)).await;
        let listed = find("Cap Test Camera B").is_some();
        if !listed && !gone {
            gone = true;
            println!("PROBE camera B disconnected at {:?}", started.elapsed());
        } else if listed && gone {
            let ready = b_feed
                .ask(camera::SetInput {
                    id: DeviceOrModelID::DeviceID(b_id.clone()),
                    settings: None,
                })
                .await;
            match ready {
                Ok(ready) => match ready.await {
                    Ok(_) => {
                        gone = false;
                        println!("PROBE camera B reopened at {:?}", started.elapsed());
                    }
                    Err(error) => println!("PROBE reopen failed: {error}"),
                },
                Err(error) => println!("PROBE reopen refused: {error}"),
            }
        }
    }
    drop(b_lock);
    handle.stop().await.unwrap();
    println!("PROBE done");
}
