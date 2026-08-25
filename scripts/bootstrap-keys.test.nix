{ pkgs, lib }:

let
  scriptsDir = ./.;
in
pkgs.runCommand "bootstrap-keys-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    inherit scriptsDir;
  }
  ''
        set -eu

        fail() { echo "FAIL: $*" >&2; exit 1; }

        assert_file() { [ -f "$1" ] || fail "expected file: $1"; }
        assert_no_path() { [ ! -e "$1" ] || fail "unexpected path exists: $1"; }

        assert_contains() {
          needle="$1"
          file="$2"
          grep -q -- "$needle" "$file" || fail "expected '$needle' in $file"
        }

        assert_not_contains() {
          needle="$1"
          file="$2"
          ! grep -q -- "$needle" "$file" || fail "did not expect '$needle' in $file"
        }

        assert_eq() {
          expected="$1"
          actual="$2"
          message="$3"
          [ "$expected" = "$actual" ] || fail "$message: expected '$expected', got '$actual'"
        }

        assert_mode() {
          file="$1"
          expected="$2"
          actual=$(stat -c '%a' "$file")
          assert_eq "$expected" "$actual" "mode for $file"
        }

        fake_repo="$TMPDIR/fakerepo"
        mkdir -p "$fake_repo"
        cp -R "$scriptsDir" "$fake_repo/scripts"
        chmod -R u+w "$fake_repo/scripts"
        chmod +x "$fake_repo/scripts/bootstrap-keys.sh" "$fake_repo/scripts/lib/patch-empty-string-field.sh"

        # The sandbox has no /usr/bin/env, so env-based shebangs cannot exec.
        # Point the copied scripts straight at the Nix-provided bash.
        sed -i "1s|^.*$|#!${pkgs.bash}/bin/bash|" \
          "$fake_repo/scripts/bootstrap-keys.sh" \
          "$fake_repo/scripts/lib/patch-empty-string-field.sh"
        bootstrap="$fake_repo/scripts/bootstrap-keys.sh"

        bin_dir="$TMPDIR/bin"
        mkdir -p "$bin_dir"

        cat > "$bin_dir/nix" <<'EOF'
    #!/bin/sh
    set -eu
    last=""
    for arg in "$@"; do last="$arg"; done

    is_eval=0
    for arg in "$@"; do
      if [ "$arg" = "eval" ]; then
        is_eval=1
      fi
    done

    if [ "$is_eval" -ne 1 ]; then
      exit 0
    fi

    attr="''${last#*#}"
    leaf="''${attr##*.}"

    if [ -f "$NIX_FAKE_ATTRS/unrelated-error" ]; then
      printf 'catastrophic fake nix failure for %s\n' "$attr" >&2
      exit 1
    fi

    attr_file="$NIX_FAKE_ATTRS/$leaf"
    if [ -f "$attr_file" ]; then
      cat "$attr_file"
      exit 0
    fi

    variant="''${NIX_FAKE_MISSING_VARIANT:-full}"
    if [ "$variant" = "leaf" ]; then
      printf "error: attribute '%s' missing\n" "$leaf" >&2
    else
      printf "error: flake '%s' does not provide attribute '%s'\n" "$last" "$attr" >&2
    fi
    exit 1
    EOF
        chmod +x "$bin_dir/nix"

        cat > "$bin_dir/ssh-keygen" <<'EOF'
    #!/bin/sh
    set -eu
    mode=""
    file=""
    comment=""
    prev=""
    for arg in "$@"; do
      if [ "$arg" = "-y" ]; then mode="print-public"; fi
      if [ "$arg" = "-t" ]; then mode="generate"; fi
      if [ "$prev" = "-f" ]; then file="$arg"; fi
      if [ "$prev" = "-C" ]; then comment="$arg"; fi
      prev="$arg"
    done

    if [ "$mode" = "print-public" ]; then
      case "''${SSH_KEYGEN_Y_FAIL:-}" in
        1) exit 1 ;;
        empty) exit 0 ;;
      esac
      printf 'ssh-ed25519 recreated-public-key\n'
      exit 0
    fi

    if [ "$mode" = "generate" ]; then
      mkdir -p "$(dirname "$file")"
      printf 'fake private key for %s\n' "$comment" > "$file"
      chmod 600 "$file"
      printf 'ssh-ed25519 generated-public-key %s\n' "$comment" > "$file.pub"
      chmod 644 "$file.pub"
      exit 0
    fi

    printf 'unexpected fake ssh-keygen invocation: %s\n' "$*" >&2
    exit 1
    EOF
        chmod +x "$bin_dir/ssh-keygen"

        cat > "$bin_dir/hostname" <<'EOF'
    #!/bin/sh
    printf 'testhost\n'
    EOF
        chmod +x "$bin_dir/hostname"

        case_name=""
        home_dir=""
        private_dir=""
        attrs_dir=""
        last_output=""
        missing_variant="full"
        ssh_y_fail=""

        write_private_flake() {
          name="$1"
          email="$2"
          signing_key="$3"
          mkdir -p "$private_dir"
          cat > "$private_dir/flake.nix" <<EOF
    {
      description = "Private dotfiles overlay";

      outputs =
        { self, ... }:
        {
          git = {
            name = "$name";
            email = "$email";
            signingKey = "$signing_key";
          };

          goto = {
            apiUrl = "http://127.0.0.1:50002";
            bookmarksFile = ./goto/database.yml;
          };

          personal.enable = false;
          opencode.imports = [ ];
          homeModules = [ ];
        };
    }
    EOF
        }

        set_attr() {
          leaf="$1"
          value="$2"
          mkdir -p "$attrs_dir"
          if [ "$value" = "__MISSING__" ]; then
            rm -f "$attrs_dir/$leaf"
          else
            printf '%s' "$value" > "$attrs_dir/$leaf"
          fi
        }

        attr_from_flake() {
          leaf="$1"
          sed -n -E "s/^[[:space:]]*$leaf[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$private_dir/flake.nix" | sed -n '1p'
        }

        sync_attrs_from_flake() {
          set_attr name "$(attr_from_flake name)"
          set_attr email "$(attr_from_flake email)"
          set_attr signingKey "$(attr_from_flake signingKey)"
        }

        setup_case() {
          case_name="$1"
          name="$2"
          email="$3"
          signing_key="$4"
          home_dir="$TMPDIR/$case_name/home"
          private_dir="$TMPDIR/$case_name/private"
          attrs_dir="$TMPDIR/$case_name/attrs"
          last_output="$TMPDIR/$case_name/output.log"
          missing_variant="full"
          ssh_y_fail=""
          mkdir -p "$home_dir" "$attrs_dir"
          write_private_flake "$name" "$email" "$signing_key"
          set_attr name "$name"
          set_attr email "$email"
          set_attr signingKey "$signing_key"
        }

        make_existing_ssh_keypair() {
          mkdir -p "$home_dir/.ssh"
          chmod 700 "$home_dir/.ssh"
          printf 'existing fake private key\n' > "$home_dir/.ssh/id_ed25519"
          chmod 600 "$home_dir/.ssh/id_ed25519"
          printf 'ssh-ed25519 existing-public-key\n' > "$home_dir/.ssh/id_ed25519.pub"
          chmod 644 "$home_dir/.ssh/id_ed25519.pub"
        }

        make_existing_opencode_keypair() {
          mkdir -p "$private_dir/keys"
          chmod 700 "$private_dir/keys"
          printf 'existing fake opencode private key\n' > "$private_dir/keys/opencode-git-signing"
          chmod 600 "$private_dir/keys/opencode-git-signing"
          printf 'ssh-ed25519 existing-opencode-public-key\n' > "$private_dir/keys/opencode-git-signing.pub"
          chmod 644 "$private_dir/keys/opencode-git-signing.pub"
        }

        run_bootstrap() {
          expected_rc="$1"
          shift
          set +e
          output=$(HOME="$home_dir" \
            DOTFILES_PRIVATE_REF="$private_dir" \
            NIX_FAKE_ATTRS="$attrs_dir" \
            NIX_FAKE_MISSING_VARIANT="$missing_variant" \
            SSH_KEYGEN_Y_FAIL="$ssh_y_fail" \
            PATH="$bin_dir:$PATH" \
            bash "$bootstrap" "$@" 2>&1)
          rc=$?
          set -e
          printf '%s\n' "$output" > "$last_output"
          [ "$rc" -eq "$expected_rc" ] || fail "$case_name expected exit $expected_rc, got $rc; output in $last_output"
        }

        # 1. Fresh bootstrap generates an SSH key, patches signingKey, and prints upload hints.
        setup_case case01-fresh "Ada Lovelace" "ada@example.test" ""
        set_attr signingKey __MISSING__
        run_bootstrap 0
        signing_key=$(attr_from_flake signingKey)
        assert_eq "~/.ssh/id_ed25519.pub" "$signing_key" "SSH signing key path"
        assert_file "$home_dir/.ssh/id_ed25519"
        assert_file "$home_dir/.ssh/id_ed25519.pub"
        assert_mode "$home_dir/.ssh/id_ed25519" 600
        assert_mode "$home_dir/.ssh/id_ed25519.pub" 644
        assert_contains "generating SSH key" "$last_output"
        assert_contains "Public keys ready for upload" "$last_output"
        assert_contains "--usage-type auth_and_signing" "$last_output"
        assert_contains "--type signing" "$last_output"
        assert_file "$private_dir/keys/opencode-git-signing"
        assert_file "$private_dir/keys/opencode-git-signing.pub"
        assert_mode "$private_dir/keys/opencode-git-signing" 600
        assert_mode "$private_dir/keys/opencode-git-signing.pub" 644
        assert_contains "generating OpenCode commit-signing key" "$last_output"
        assert_contains 'opencode-testhost' "$last_output"

        # 2. Idempotent rerun reuses the same state and does not generate another key.
        sync_attrs_from_flake
        run_bootstrap 0
        assert_contains "already bootstrapped" "$last_output"
        assert_not_contains "Public keys ready for upload" "$last_output"
        assert_not_contains "generating OpenCode commit-signing key" "$last_output"

        # 3. A configured signing key and existing keypair are left unchanged.
        setup_case case03-configured "Grace Hopper" "grace@example.test" "~/.ssh/custom.pub"
        make_existing_ssh_keypair
        make_existing_opencode_keypair
        run_bootstrap 0
        assert_eq "~/.ssh/custom.pub" "$(attr_from_flake signingKey)" "configured signing key"
        assert_contains "already bootstrapped" "$last_output"
        assert_not_contains "Public keys ready for upload" "$last_output"
        assert_not_contains "Upload commands:" "$last_output"
        assert_not_contains "generating OpenCode commit-signing key" "$last_output"

        # 4. An empty signing key adopts an existing default SSH keypair.
        setup_case case04-adopt-existing "Existing User" "existing@example.test" ""
        set_attr signingKey __MISSING__
        make_existing_ssh_keypair
        run_bootstrap 0
        assert_eq "~/.ssh/id_ed25519.pub" "$(attr_from_flake signingKey)" "adopted signing key path"
        assert_not_contains "generating SSH key" "$last_output"
        assert_file "$private_dir/keys/opencode-git-signing"

        # 5. Existing SSH private key with missing public key is repaired using ssh-keygen -y.
        setup_case case05-recreate-ssh-pub "SSH Repair" "repair@example.test" "~/.ssh/id_ed25519.pub"
        make_existing_ssh_keypair
        rm -f "$home_dir/.ssh/id_ed25519.pub"
        run_bootstrap 0
        assert_file "$home_dir/.ssh/id_ed25519.pub"
        assert_mode "$home_dir/.ssh/id_ed25519.pub" 644
        assert_contains "recreating SSH public key" "$last_output"

        # 6. Failed/empty ssh-keygen -y leaves no temporary or final public key behind.
        setup_case case06-ssh-pub-empty "SSH Empty" "empty@example.test" "~/.ssh/id_ed25519.pub"
        make_existing_ssh_keypair
        rm -f "$home_dir/.ssh/id_ed25519.pub"
        ssh_y_fail="empty"
        run_bootstrap 0
        assert_no_path "$home_dir/.ssh/id_ed25519.pub"
        assert_contains "could not recreate $home_dir/.ssh/id_ed25519.pub" "$last_output"

        # 6b. A failing ssh-keygen -y also leaves no temporary or final public key behind.
        setup_case case06b-ssh-pub-fail "SSH Fail" "fail@example.test" "~/.ssh/id_ed25519.pub"
        make_existing_ssh_keypair
        rm -f "$home_dir/.ssh/id_ed25519.pub"
        ssh_y_fail="1"
        run_bootstrap 0
        assert_no_path "$home_dir/.ssh/id_ed25519.pub"
        assert_contains "could not recreate $home_dir/.ssh/id_ed25519.pub" "$last_output"

        # 7. Empty git.name and git.email are fatal.
        setup_case case07-empty-name "" "empty-name@example.test" ""
        run_bootstrap 1
        assert_contains "git.name is empty" "$last_output"

        setup_case case07-empty-email "Empty Email" "" ""
        run_bootstrap 1
        assert_contains "git.email is empty" "$last_output"

        # 8. Missing private flake is fatal.
        setup_case case08-missing-private "Missing" "missing@example.test" ""
        rm -f "$private_dir/flake.nix"
        run_bootstrap 1
        assert_contains "private flake missing" "$last_output"

        # 9. Non-missing-attribute nix eval failures surface stderr and exit 1.
        setup_case case09-eval-hard-failure "Eval" "eval@example.test" ""
        : > "$attrs_dir/unrelated-error"
        run_bootstrap 1
        assert_contains "failed to evaluate private flake attribute git.name" "$last_output"
        assert_contains "catastrophic fake nix failure for git.name" "$last_output"

        # 10. --show prints upload hints even with no changes.
        setup_case case10-show "Show User" "show@example.test" "~/.ssh/id_ed25519.pub"
        make_existing_ssh_keypair
        make_existing_opencode_keypair
        run_bootstrap 0 --show
        assert_contains "Public keys ready for upload" "$last_output"
        assert_contains "glab ssh-key add" "$last_output"
        assert_contains "gh ssh-key add" "$last_output"
        assert_contains "--type signing" "$last_output"
        assert_contains 'opencode-testhost' "$last_output"

        # 11. Flag misuse exits 2 before doing any bootstrap work.
        setup_case case11-name-without-value "Flags" "flags@example.test" ""
        run_bootstrap 2 --name
        assert_contains "--name requires a value" "$last_output"

        setup_case case11-unknown-flag "Flags" "flags@example.test" ""
        run_bootstrap 2 --definitely-unknown
        assert_contains "unknown argument" "$last_output"

        # 12. An existing OpenCode signing keypair is never regenerated.
        setup_case case12-opencode-exists "Kept Key" "kept@example.test" "~/.ssh/id_ed25519.pub"
        make_existing_ssh_keypair
        make_existing_opencode_keypair
        run_bootstrap 0
        assert_contains "already bootstrapped" "$last_output"
        assert_not_contains "generating OpenCode commit-signing key" "$last_output"
        assert_eq "existing fake opencode private key" "$(cat "$private_dir/keys/opencode-git-signing")" \
          "existing opencode private key preserved"

        # 13. A missing OpenCode signing public key is repaired via ssh-keygen -y.
        setup_case case13-opencode-pub-missing "OC Repair" "oc-repair@example.test" "~/.ssh/id_ed25519.pub"
        make_existing_ssh_keypair
        make_existing_opencode_keypair
        rm -f "$private_dir/keys/opencode-git-signing.pub"
        run_bootstrap 0
        assert_file "$private_dir/keys/opencode-git-signing.pub"
        assert_mode "$private_dir/keys/opencode-git-signing.pub" 644
        assert_contains "recreating OpenCode signing public key" "$last_output"

        echo "all bootstrap-keys assertions passed"
        touch "$out"
  ''
