let googleCredential = null;
  function initGoogle() {
    if (typeof google !== "undefined") {
      google.accounts.id.initialize({
        client_id: "730968670456-4kvre8am1isuqe3dbmdqs8845ntog6cq.apps.googleusercontent.com",
        callback: handleGoogle
      });
      google.accounts.id.renderButton(
        document.getElementById("google-signin"),
        { theme: "outline", size: "large", text: "signin_with", locale: "pt-PT" }
      );
    } else {
      setTimeout(initGoogle, 100);
    }
  }
  function handleGoogle(res) {
    googleCredential = res.credential;
    const payload = JSON.parse(atob(res.credential.split(".")[1]));
    document.getElementById("user-email").textContent = payload.email;
    document.getElementById("google_token").value = res.credential;
    document.getElementById("google-user").classList.remove("hidden");
    document.getElementById("google-signin").classList.add("hidden");
  }
  document.addEventListener("DOMContentLoaded", initGoogle);
