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
      pkgs.gawk
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

        cat > "$bin_dir/gpg" <<'EOF'
    #!/bin/sh
    set -eu
    mkdir -p "$GPG_FAKE_STATE"
    state_file="$GPG_FAKE_STATE/keys.colon"
    counter_file="$GPG_FAKE_STATE/generate.count"
    [ -f "$state_file" ] || : > "$state_file"

    last=""
    cmd=""
    export_id=""
    prev=""
    for arg in "$@"; do
      last="$arg"
      if [ "$arg" = "--list-secret-keys" ]; then cmd="list"; fi
      if [ "$arg" = "--quick-generate-key" ]; then cmd="generate"; fi
      if [ "$arg" = "--export" ]; then cmd="export"; fi
      if [ "$prev" = "--export" ]; then export_id="$arg"; fi
      prev="$arg"
    done

    if [ "$cmd" = "list" ]; then
      query="$last"
      awk -F: -v q="$query" '
        $1 == "sec" {
          if (block != "" && matched) printf "%s", block
          block = $0 "\n"
          matched = index($5, q) > 0
          next
        }
        {
          block = block $0 "\n"
          if (index($0, q) > 0) matched = 1
        }
        END {
          if (block != "" && matched) printf "%s", block
        }
      ' "$state_file"
      exit 0
    fi

    if [ "$cmd" = "generate" ]; then
      uid="$2"
      count=0
      [ -f "$counter_file" ] && count=$(cat "$counter_file")
      count=$((count + 1))
      printf '%s' "$count" > "$counter_file"
      key_id=$(printf 'F00DBABE%08d' "$count")
      epoch=$(date +%s)
      {
        printf 'sec:u:255:22:%s:%s::::::scESC::::::23::0:\n' "$key_id" "$epoch"
        printf 'uid:u::::%s::FAKEHASH::%s::::::::::0:\n' "$epoch" "$uid"
      } >> "$state_file"
      exit 0
    fi

    if [ "$cmd" = "export" ]; then
      printf '%s\n' '-----BEGIN PGP PUBLIC KEY BLOCK-----'
      printf 'fake armored public key for %s\n' "$export_id"
      printf '%s\n' '-----END PGP PUBLIC KEY BLOCK-----'
      exit 0
    fi

    printf 'unexpected fake gpg invocation: %s\n' "$*" >&2
    exit 1
    EOF
        chmod +x "$bin_dir/gpg"

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
        export_dir=""
        attrs_dir=""
        gpg_state=""
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
          export_dir="$TMPDIR/$case_name/export"
          attrs_dir="$TMPDIR/$case_name/attrs"
          gpg_state="$TMPDIR/$case_name/gpg"
          last_output="$TMPDIR/$case_name/output.log"
          missing_variant="full"
          ssh_y_fail=""
          mkdir -p "$home_dir" "$export_dir" "$attrs_dir" "$gpg_state"
          write_private_flake "$name" "$email" "$signing_key"
          set_attr name "$name"
          set_attr email "$email"
          set_attr signingKey "$signing_key"
        }

        append_secret_key() {
          key_id="$1"
          epoch="$2"
          uid="$3"
          mkdir -p "$gpg_state"
          {
            printf 'sec:u:255:22:%s:%s::::::scESC::::::23::0:\n' "$key_id" "$epoch"
            printf 'uid:u::::%s::FAKEHASH::%s::::::::::0:\n' "$epoch" "$uid"
          } >> "$gpg_state/keys.colon"
        }

        make_existing_ssh_keypair() {
          mkdir -p "$home_dir/.ssh"
          chmod 700 "$home_dir/.ssh"
          printf 'existing fake private key\n' > "$home_dir/.ssh/id_ed25519"
          chmod 600 "$home_dir/.ssh/id_ed25519"
          printf 'ssh-ed25519 existing-public-key\n' > "$home_dir/.ssh/id_ed25519.pub"
          chmod 644 "$home_dir/.ssh/id_ed25519.pub"
        }

        run_bootstrap() {
          expected_rc="$1"
          shift
          set +e
          output=$(HOME="$home_dir" \
            DOTFILES_PRIVATE_REF="$private_dir" \
            DOTFILES_KEY_EXPORT_DIR="$export_dir" \
            NIX_FAKE_ATTRS="$attrs_dir" \
            NIX_FAKE_MISSING_VARIANT="$missing_variant" \
            GPG_FAKE_STATE="$gpg_state" \
            SSH_KEYGEN_Y_FAIL="$ssh_y_fail" \
            PATH="$bin_dir:$PATH" \
            bash "$bootstrap" "$@" 2>&1)
          rc=$?
          set -e
          printf '%s\n' "$output" > "$last_output"
          [ "$rc" -eq "$expected_rc" ] || fail "$case_name expected exit $expected_rc, got $rc; output in $last_output"
        }

        # 1. Fresh bootstrap generates a GPG key, patches signingKey, creates SSH, exports, and prints upload hints.
        setup_case case01-fresh "Ada Lovelace" "ada@example.test" ""
        set_attr signingKey __MISSING__
        run_bootstrap 0
        signing_key=$(attr_from_flake signingKey)
        [ -n "$signing_key" ] || fail "fresh bootstrap did not patch signingKey"
        assert_eq "F00DBABE00000001" "$signing_key" "generated signing key id"
        assert_file "$home_dir/.ssh/id_ed25519"
        assert_file "$home_dir/.ssh/id_ed25519.pub"
        assert_mode "$home_dir/.ssh/id_ed25519" 600
        assert_mode "$home_dir/.ssh/id_ed25519.pub" 644
        assert_file "$export_dir/gpg-signing-key-$signing_key.asc"
        assert_contains "fake armored public key for $signing_key" "$export_dir/gpg-signing-key-$signing_key.asc"
        assert_contains "generating GPG signing key for Ada Lovelace <ada@example.test>" "$last_output"
        assert_contains "Public keys ready for upload" "$last_output"
        assert_contains "glab gpg-key add" "$last_output"
        assert_eq "1" "$(cat "$gpg_state/generate.count")" "fresh bootstrap generation count"

        # 2. Idempotent rerun reuses the same state and does not generate another key.
        sync_attrs_from_flake
        before_state=$(cat "$gpg_state/keys.colon")
        run_bootstrap 0
        after_state=$(cat "$gpg_state/keys.colon")
        assert_eq "$before_state" "$after_state" "idempotent rerun should not mutate GPG state"
        assert_eq "1" "$(cat "$gpg_state/generate.count")" "idempotent rerun generation count"
        assert_contains "already bootstrapped" "$last_output"
        assert_not_contains "Public keys ready for upload" "$last_output"

        # 3. Configured signingKey present in the keyring is a no-change run with no upload hints.
        setup_case case03-configured-present "Grace Hopper" "grace@example.test" "PRESENT000000001"
        append_secret_key PRESENT000000001 200 "Grace Hopper <grace@example.test>"
        make_existing_ssh_keypair
        run_bootstrap 0
        assert_contains "GPG signing key already present: PRESENT000000001" "$last_output"
        assert_contains "already bootstrapped" "$last_output"
        assert_not_contains "Public keys ready for upload" "$last_output"
        assert_not_contains "Upload commands:" "$last_output"

        # 4. Configured signingKey absent from the keyring warns twice but continues.
        setup_case case04-configured-absent "No Key" "nokey@example.test" "ABSENT0000000001"
        make_existing_ssh_keypair
        run_bootstrap 0
        assert_contains "git.signingKey is set to ABSENT0000000001" "$last_output"
        assert_contains "import the secret key or replace git.signingKey" "$last_output"
        assert_contains "already bootstrapped" "$last_output"

        # 5. Existing keys for the email adopt the newest sec record and do not generate a new key.
        setup_case case05-adopt-newest "Existing User" "existing@example.test" ""
        missing_variant="leaf"
        set_attr signingKey __MISSING__
        append_secret_key OLDKEY0000000001 100 "Existing User <existing@example.test>"
        append_secret_key NEWKEY0000000001 200 "Existing User <existing@example.test>"
        make_existing_ssh_keypair
        run_bootstrap 0
        assert_eq "NEWKEY0000000001" "$(attr_from_flake signingKey)" "newest existing key should be patched"
        assert_not_contains "generating GPG signing key" "$last_output"
        [ ! -f "$gpg_state/generate.count" ] || fail "adopting existing key should not quick-generate"

        # 6. Existing SSH private key with missing public key is repaired using ssh-keygen -y.
        setup_case case06-recreate-ssh-pub "SSH Repair" "repair@example.test" "REPAIR000000001"
        append_secret_key REPAIR000000001 200 "SSH Repair <repair@example.test>"
        make_existing_ssh_keypair
        rm -f "$home_dir/.ssh/id_ed25519.pub"
        run_bootstrap 0
        assert_file "$home_dir/.ssh/id_ed25519.pub"
        assert_mode "$home_dir/.ssh/id_ed25519.pub" 644
        assert_contains "recreating SSH public key" "$last_output"

        # 7. Failed/empty ssh-keygen -y leaves no temporary or final public key behind.
        setup_case case07-ssh-pub-empty "SSH Empty" "empty@example.test" "EMPTY0000000001"
        append_secret_key EMPTY0000000001 200 "SSH Empty <empty@example.test>"
        make_existing_ssh_keypair
        rm -f "$home_dir/.ssh/id_ed25519.pub"
        ssh_y_fail="empty"
        run_bootstrap 0
        assert_no_path "$home_dir/.ssh/id_ed25519.pub"
        assert_contains "could not recreate $home_dir/.ssh/id_ed25519.pub" "$last_output"

        # 7b. A failing ssh-keygen -y also leaves no temporary or final public key behind.
        setup_case case07b-ssh-pub-fail "SSH Fail" "fail@example.test" "FAIL0000000001"
        append_secret_key FAIL0000000001 200 "SSH Fail <fail@example.test>"
        make_existing_ssh_keypair
        rm -f "$home_dir/.ssh/id_ed25519.pub"
        ssh_y_fail="1"
        run_bootstrap 0
        assert_no_path "$home_dir/.ssh/id_ed25519.pub"
        assert_contains "could not recreate $home_dir/.ssh/id_ed25519.pub" "$last_output"

        # 8. Empty git.name and git.email are fatal.
        setup_case case08-empty-name "" "empty-name@example.test" ""
        run_bootstrap 1
        assert_contains "git.name is empty" "$last_output"

        setup_case case08-empty-email "Empty Email" "" ""
        run_bootstrap 1
        assert_contains "git.email is empty" "$last_output"

        # 9. Missing private flake is fatal.
        setup_case case09-missing-private "Missing" "missing@example.test" ""
        rm -f "$private_dir/flake.nix"
        run_bootstrap 1
        assert_contains "private flake missing" "$last_output"

        # 10. Non-missing-attribute nix eval failures surface stderr and exit 1.
        setup_case case10-eval-hard-failure "Eval" "eval@example.test" ""
        : > "$attrs_dir/unrelated-error"
        run_bootstrap 1
        assert_contains "failed to evaluate private flake attribute git.name" "$last_output"
        assert_contains "catastrophic fake nix failure for git.name" "$last_output"

        # 11. --show prints upload hints even with no changes.
        setup_case case11-show "Show User" "show@example.test" "SHOW00000000001"
        append_secret_key SHOW00000000001 200 "Show User <show@example.test>"
        make_existing_ssh_keypair
        run_bootstrap 0 --show
        assert_contains "Public keys ready for upload" "$last_output"
        assert_contains "glab gpg-key add" "$last_output"
        assert_contains "gh ssh-key add" "$last_output"

        # 12. Flag misuse exits 2 before doing any bootstrap work.
        setup_case case12-name-without-value "Flags" "flags@example.test" ""
        run_bootstrap 2 --name
        assert_contains "--name requires a value" "$last_output"

        setup_case case12-unknown-flag "Flags" "flags@example.test" ""
        run_bootstrap 2 --definitely-unknown
        assert_contains "unknown argument" "$last_output"

        echo "all bootstrap-keys assertions passed"
        touch "$out"
  ''
