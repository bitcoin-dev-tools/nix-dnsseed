{
  config,
  lib,
  pkgs,
  ...
}:
let
  forgejo = lib.getExe config.services.forgejo.package;
  stateDir = config.services.forgejo.stateDir;
  adminUser = "willcl-ark";
  adminEmail = "will@256k1.dev";
  forgejoBundle = {
    forgejoUrl = "http://127.0.0.1:3001";
    anubisBind = "127.0.0.1:3002";
  };

  adminInit = pkgs.writeShellScript "forgejo-admin-init" ''
    set -euo pipefail

    if ${forgejo} admin user list | ${pkgs.gawk}/bin/awk -v user=${lib.escapeShellArg adminUser} 'NR > 1 && $2 == user { found = 1 } END { exit found ? 0 : 1 }'; then
      exit 0
    fi

    password="$(cat ${lib.escapeShellArg config.sops.secrets.forgejo-admin-password.path})"
    ${forgejo} admin user create \
      --admin \
      --username ${lib.escapeShellArg adminUser} \
      --password "$password" \
      --email ${lib.escapeShellArg adminEmail} \
      --must-change-password=false
  '';
in
{
  sops.secrets.forgejo-admin-password = {
    owner = "forgejo";
    group = "forgejo";
    mode = "0400";
  };
  sops.secrets.forgejo-secret-key = {
    owner = "forgejo";
    group = "forgejo";
    mode = "0400";
  };
  sops.secrets.forgejo-internal-token = {
    owner = "forgejo";
    group = "forgejo";
    mode = "0400";
  };
  sops.secrets.forgejo-oauth2-jwt-secret = {
    owner = "forgejo";
    group = "forgejo";
    mode = "0400";
  };
  sops.secrets.forgejo-mailer-password = {
    owner = "forgejo";
    group = "forgejo";
    mode = "0400";
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;

    database.type = "sqlite3";
    dump.enable = true;
    lfs.enable = true;

    settings = {
      DEFAULT = {
        APP_NAME = "code.fish.foo";
      };

      server = {
        DOMAIN = "code.fish.foo";
        ROOT_URL = "https://code.fish.foo/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3001;
        START_SSH_SERVER = false;
        DISABLE_SSH = false;
        SSH_DOMAIN = "code.fish.foo";
        SSH_PORT = 22;
        SSH_USER = "forgejo";
        OFFLINE_MODE = true;
      };

      session = {
        COOKIE_SECURE = true;
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = false;
        ENABLE_BASIC_AUTHENTICATION = false;
        ENABLE_NOTIFY_MAIL = true;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = false;
      };

      mailer = {
        ENABLED = true;
        FROM = "Forgejo <forgejo@fish.foo>";
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.mailbox.org";
        SMTP_PORT = 465;
        USER = "will@256k1.dev";
        PASSWD_URI = "file:${config.sops.secrets.forgejo-mailer-password.path}";
      };

      admin = {
        DISABLE_REGULAR_ORG_CREATION = true;
      };

      security = {
        GLOBAL_TWO_FACTOR_REQUIREMENT = "admin";
        LOGIN_REMEMBER_DAYS = 7;
        DISABLE_QUERY_AUTH_TOKEN = true;
        DISABLE_WEBHOOKS = true;
      };

      repository = {
        DEFAULT_PRIVATE = "public";
        DEFAULT_BRANCH = "master";
        DISABLE_HTTP_GIT = false;
        ENABLE_PUSH_CREATE_USER = false;
        ENABLE_PUSH_CREATE_ORG = false;
        DISABLED_REPO_UNITS = "repo.packages";
        DEFAULT_REPO_UNITS = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.actions";
        DEFAULT_MIRROR_REPO_UNITS = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.actions";
        ALLOW_ADOPTION_OF_UNADOPTED_REPOSITORIES = false;
        ALLOW_DELETION_OF_UNADOPTED_REPOSITORIES = false;
        DISABLE_MIGRATIONS = false;
      };

      migrations = {
        ALLOWED_DOMAINS = "github.com,*.github.com";
        ALLOW_LOCALNETWORKS = false;
      };

      "repository.upload" = {
        ENABLED = false;
      };

      actions = {
        ENABLED = true;
      };

      packages = {
        ENABLED = false;
      };

      oauth2 = {
        ENABLED = false;
      };

      openid = {
        ENABLE_OPENID_SIGNIN = false;
        ENABLE_OPENID_SIGNUP = false;
      };

      api = {
        ENABLE_SWAGGER = false;
      };

      log = {
        LEVEL = "Info";
      };
    };

    secrets = {
      security = {
        SECRET_KEY = lib.mkForce config.sops.secrets.forgejo-secret-key.path;
        INTERNAL_TOKEN = lib.mkForce config.sops.secrets.forgejo-internal-token.path;
      };
      oauth2 = {
        JWT_SECRET = lib.mkForce config.sops.secrets.forgejo-oauth2-jwt-secret.path;
      };
    };
  };

  services.caddy.virtualHosts."code.fish.foo".extraConfig = ''
    reverse_proxy ${forgejoBundle.anubisBind} {
      header_up X-Forwarded-For {client_ip}
      header_up X-Real-IP {client_ip}
      header_up X-Http-Version {http.request.proto}
    }
  '';

  services.anubis.instances.forgejo.settings = {
    TARGET = forgejoBundle.forgejoUrl;
    BIND = forgejoBundle.anubisBind;
    BIND_NETWORK = "tcp";
    OG_PASSTHROUGH = true;
  };

  systemd.services.forgejo = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };

  systemd.services.forgejo-admin-init = {
    description = "Create the initial Forgejo administrator";
    after = [
      "forgejo.service"
      "sops-install-secrets.service"
    ];
    requires = [ "forgejo.service" ];
    wants = [ "sops-install-secrets.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.services.forgejo.package
      pkgs.gawk
    ];
    environment = {
      USER = config.services.forgejo.user;
      HOME = stateDir;
      FORGEJO_WORK_DIR = stateDir;
      FORGEJO_CUSTOM = config.services.forgejo.customDir;
    };
    serviceConfig = {
      Type = "oneshot";
      User = config.services.forgejo.user;
      Group = config.services.forgejo.group;
      WorkingDirectory = stateDir;
      ExecStart = adminInit;
    };
  };
}
