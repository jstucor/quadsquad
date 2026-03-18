#pragma once

// Procedural per-shot recoil state, owned by Camera.
//
// Each shot splits its kick into two halves:
//   bounce — elastic kick that springs back to 0 over ~0.2 s
//   drift  — accumulated net offset (~50% of kick) that decays slowly over ~1 s;
//             the player must manually pull the view back to re-centre
//   yaw    — horizontal shake that fully recovers within ~0.1 s
//
// getFront() adds (bounce + drift) to pitch and yaw to yaw, but never
// touches the stored pitch/yaw values so mouse input feels unaffected.
struct RecoilState {
    float bounce = 0.f;   // degrees, springs to 0
    float drift  = 0.f;   // degrees, slow decay — manual correction required
    float yaw    = 0.f;   // degrees, fast full recovery
};
