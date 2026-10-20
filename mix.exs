defmodule NervesSystemRk3326Frame156.MixProject do
  use Mix.Project

  @app :nerves_system_rk3326_frame156
  @github_organization "bbangert"
  @source_url "https://github.com/#{@github_organization}/#{@app}"
  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      compilers: Mix.compilers() ++ [:nerves_package],
      nerves_package: nerves_package(),
      description: description(),
      package: package(),
      deps: deps(),
      aliases: [
        loadconfig: [&bootstrap/1],
        generate_fwup_conf: &generate_fwup_conf/1
      ]
    ]
  end

  def application do
    []
  end

  defp bootstrap(args) do
    set_target()
    Application.start(:nerves_bootstrap)
    Mix.Task.run("loadconfig", args)
  end

  defp nerves_package do
    [
      type: :system,
      artifact_sites: [
        {:github_releases, "#{@github_organization}/#{@app}"}
      ],
      build_runner_opts: build_runner_opts(),
      platform: Nerves.System.BR,
      platform_config: [
        defconfig: "nerves_defconfig"
      ],
      # The :env key is an optional experimental feature for adding environment
      # variables to the crosscompile environment. These are intended for
      # llvm-based tooling that may need more precise processor information.
      env: [
        {"TARGET_ARCH", "aarch64"},
        {"TARGET_CPU", "cortex_a35"},
        {"TARGET_OS", "linux"},
        {"TARGET_ABI", "gnu"},
        {"TARGET_GCC_FLAGS",
         "-mabi=lp64 -fstack-protector-strong -mcpu=cortex-a35 -fPIE -pie -Wl,-z,now -Wl,-z,relro"}
      ],
      checksum: package_files()
    ]
  end

  defp deps do
    [
      {:nerves, "~> 1.11 or ~> 2.0 or ~> 2.0.0-dev", runtime: false},
      {:nerves_system_br, "1.35.2", runtime: false},
      {:nerves_toolchain_aarch64_nerves_linux_gnu, "~> 15.3.0", runtime: false},
      {:nerves_system_linter, "~> 0.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Nerves System - Pastigio FRAME156 photo frame (Rockchip RK3326)"
  end

  defp package do
    [
      files: package_files(),
      licenses: ["GPL-2.0-only", "GPL-2.0-or-later"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp package_files do
    [
      "board",
      "dts",
      "fwup_include",
      "linux",
      "package",
      "patches",
      # Not all of rootfs_overlay: a local build may have the touch
      # firmware in lib/firmware/silead, which can't be redistributed.
      "rootfs_overlay/etc",
      "rootfs_overlay/usr",
      "scripts/rk-images.py",
      "scripts/rk-resource.py",
      "uboot",
      "Config.in",
      "external.mk",
      "fwup-ops.conf",
      "fwup.conf.eex",
      "mix.exs",
      "nerves_defconfig",
      "post-build.sh",
      "post-createfs.sh",
      "README.md",
      "VERSION"
    ]
  end

  defp build_runner_opts() do
    # Download source files first to get download errors right away.
    [make_args: primary_site() ++ ["source", "all", "legal-info"]]
  end

  defp primary_site() do
    case System.get_env("BR2_PRIMARY_SITE") do
      nil -> []
      primary_site -> ["BR2_PRIMARY_SITE=#{primary_site}"]
    end
  end

  defp set_target() do
    if function_exported?(Mix, :target, 1) do
      apply(Mix, :target, [:target])
    else
      System.put_env("MIX_TARGET", "target")
    end
  end

  defp generate_fwup_conf(_args) do
    template_path = Path.join(__DIR__, "fwup.conf.eex")
    output_path = Path.join(__DIR__, "fwup.conf")

    Mix.shell().info("Generating fwup.conf")

    content = EEx.eval_file(template_path)
    File.write!(output_path, content)
    Mix.shell().info("Successfully generated #{output_path}")
  end
end
