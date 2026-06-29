using namespace System.Collections.Generic
using namespace System.IO


# An input within a chaiNNer chain that can be overridden by workflows.
class ChainInput {
	# The name used to refer to the input when defining overrides in workflows.
	[string] $Name

	# The override ID. Can be obtained in chaiNNer by right-clicking and selecting 'Copy Input Override Id'.
	[string] $ID
	
	# If the input's value type is a path, set to true to specify that the path is relative to the
	# project directory and should be resolved to an absolute path before passing to chaiNNer.
	# Useful for specifying model paths (e.g. 'models/4x-PBRify_UpscalerV4.onnx')
	[bool] $IsRelativePath = $false

	# If the input's value type is a path, throw an error if it doesn't exist before attempting to run the chain.
	[bool] $PathMustExist = $false
}


# A chaiNNer chain used in workflows to upscale textures.
class Chain {
	# The name of the chain (basename of the chain file.)
	[string] $Name

	# The input override ID for the 'Directory' input of the 'Load Images' node.
	# Used by workflows to point it's chain to the correct texture input directory.
	[string] $LoadDirectoryInputID

	# The input override ID for the 'Directory' input of the 'Save Images' node.
	# Used by workflows to point it's chain to the correct texture output directory.
	[string] $SaveDirectoryInputID

	# The inputs that can be overriden by workflows when running the chain.
	[Dictionary[string, ChainInput]] $Inputs = [Dictionary[string, ChainInput]]::new()


	[string] GetPath() {
		$chain_path = Join-Path (Get-ChainsDir) "$( $this.Name ).chn"

		if (-not (Test-Path -LiteralPath $chain_path -PathType Leaf)) {
			throw "Chain file does not exist: ${chain_path}"
		}

		return $chain_path
	}
}


# Overrides a node's input within a chain.
# Used by workflows to supply upscale model filepaths or change some other input data.
class InputOverride {
	# The chain input to override.
	[ChainInput] $ChainInput

	# The value to provide when overriding the input.
	[string] $Value
}


# Defines a method for upscaling textures.
# Consists of a chaiNNer chain used to process the textures, and the data
# that will be provided to the chain (model files, etc.) when running it.
class Workflow {
	# The name of the workflow. Will serve as the name of the subdirectories under `textures/original/`
	# and `textures/upscaled/` where textures associated with the workflow are placed.
	[string] $Name

	# The chain used to process the textures.
	# If null, no textures are processed. (Used for the dummy workflow 'Manual' since they're upscaled by hand.)
	[Chain] $Chain

	# The inputs to override when running the chain.
	[InputOverride[]] $InputOverrides


	# Gets the directory where original textures are stored for this workflow.
	[string] GetOriginalTexturesDir([bool] $what_if_preference) {
		$dir = Join-Path (Get-OriginalTexturesDir -WhatIf:$what_if_preference) $this.Name
		Initialize-Directory $dir -WhatIf:$what_if_preference
		return $dir
	}

	# Gets the directory where the final, upscaled & optimized textures are stored for this workflow.
	[string] GetUpscaledTexturesDir([bool] $what_if_preference) {
		$dir = Join-Path (Get-UpscaledTexturesDir -WhatIf:$what_if_preference) $this.Name
		Initialize-Directory $dir -WhatIf:$what_if_preference
		return $dir
	}

	# Gets the directory where files (original/upscaled textures, input overrides)
	# are staged when executing this workflow.
	[string] GetBuildDir([bool] $what_if_preference) {
		$dir = Join-Path (Get-WorkflowsBuildDir -WhatIf:$what_if_preference) $this.Name
		Initialize-Directory $dir -WhatIf:$what_if_preference
		return $dir
	}

	# Gets the directory where input (original) textures are staged when executing this workflow.
	[string] GetBuildInputDir([bool] $what_if_preference) {
		$dir = Join-Path $this.GetBuildDir($what_if_preference) 'in/'
		Initialize-Directory $dir -WhatIf:$what_if_preference
		return $dir
	}

	# Gets the directory where output (upscaled/optimized) textures are staged when executing this workflow.
	[string] GetBuildOutputDir([bool] $what_if_preference) {
		$dir = Join-Path $this.GetBuildDir($what_if_preference) 'out/'
		Initialize-Directory $dir -WhatIf:$what_if_preference
		return $dir
	}
}


# Assigns a set of textures to an upscale workflow.
class TextureGroup {
	# The name of the texture group.
	[string] $Name

	# The workflow used to upscale the textures.
	# If null, the textures will not be obtained or upscaled.
	[Workflow] $Workflow

	# The names of the textures belonging to the group.
	# (Basename of the file with no extension or subdirectory, e.g. 'airlock-door-bolt')
	[string[]] $TextureNames
}


# Options configuring which textures get upscaled and which workflows to use.
class UpscaleOptions {
	# The defined chains that can be used in workflows, by name.
	[Dictionary[string, Chain]] $Chains = [Dictionary[string, Chain]]::new()

	# The defined texture upscale workflows, by name.
	[Dictionary[string, Workflow]] $Workflows = [Dictionary[string, Workflow]]::new()

	# The defined groups that assign textures to their upscale workflows, by name.
	[Dictionary[string, TextureGroup]] $TextureGroups = [Dictionary[string, TextureGroup]]::new()

	# The upscale workflow to use on textures unless otherwise specified.
	[Workflow] $DefaultWorkflow = $null

	# If enabled, emits a warning when a texture added to a group was previously assigned to another group.
	[bool] $WarnOnGroupReassignment = $false

	# The minimum width x height in pixels a texture must be to be including in upscaling.
	[int] $MinimumTextureSize = 0

	# Maps texture names to their respective texture groups.
	[Dictionary[string, TextureGroup]] $TextureGroupMap = [Dictionary[string, TextureGroup]]::new()


	UpscaleOptions([string] $json) {
		$raw_options = $json | ConvertFrom-Json -ErrorAction Stop

		$this.WarnOnGroupReassignment = $raw_options.WarnOnGroupReassignment

		foreach ($chain in $raw_options.Chains) {
			$this.AddChain(
				$chain.Name,
				$chain.LoadDirectoryInputID,
				$chain.SaveDirectoryInputID,
				$chain.Inputs
			)
		}

		foreach ($workflow in $raw_options.Workflows) {
			$this.AddWorkflow($workflow.Name, $workflow.Chain, $workflow.InputOverrides)
		}

		if ($raw_options.DefaultWorkflow) {
			$default_workflow = $this.Workflows[$raw_options.DefaultWorkflow]

			if ($null -eq $default_workflow) {
				throw "'DefaultWorkflow': Workflow '$( $raw_options.DefaultWorkflow )' does not exist."
			}

			$this.DefaultWorkflow = $default_workflow
		}

		if ($raw_options.MinimumTextureSize) {
			[int] $min_size = 0

			if (-not [int]::TryParse($raw_options.MinimumTextureSize, [ref]$min_size)) {
				throw "'MinimumTextureSize' must be a valid integer."
			}

			$this.MinimumTextureSize = $min_size
		}

		foreach ($group in $raw_options.TextureGroups) {
			$this.AddTextureGroup($group.Name, $group.Workflow, $group.TextureNames)
		}
	}


	[void] AddChain([string] $name, [string] $load_dir_id, [string] $save_dir_id, [ChainInput[]] $chain_inputs) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			throw "In 'Chains': 'Name' must not be empty."
		}

		if ([string]::IsNullOrWhiteSpace($load_dir_id)) {
			throw "In chain '${name}': 'LoadDirectoryInputID' must not be empty."
		}

		if ([string]::IsNullOrWhiteSpace($save_dir_id)) {
			throw "In chain '${name}': 'SaveDirectoryInputID' must not be empty."
		}

		if ($this.Chains.ContainsKey($name)) {
			throw "In chain '${name}': A chain named '${name}' already exists."
		}

		$chain = [Chain]::new()
		$chain.Name = $name
		$chain.LoadDirectoryInputID = $load_dir_id
		$chain.SaveDirectoryInputID = $save_dir_id

		foreach ($chain_input in $chain_inputs) {
			if ([string]::IsNullOrWhiteSpace($chain_input.Name)) {
				throw "In chain '${name}': In 'Inputs': 'Name' must not be empty."
			}
			elseif ([string]::IsNullOrWhiteSpace($chain_input.ID)) {
				throw "In chain '${name}': Input '$( $chain_input.Name )': 'ID' must not be empty."
			}

			$chain.Inputs[$chain_input.Name] = $chain_input
		}

		$this.Chains[$name] = $chain
	}


	[void] AddWorkflow([string] $name, [string] $chain_name, [object[]] $input_overrides) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			throw "In 'Workflows': 'Name' must not be empty."
		}

		if (-not (IsValidFilename $name)) {
			throw "In Workflow '${name}': Workflow name must contain only characters safe for filenames."
		}

		if ($this.Workflows.ContainsKey($name)) {
			throw "In Workflow '${name}': A Workflow named '${name}' already exists."
		}

		[Chain]$chain = $null

		if ($chain_name) {
			$chain = $this.Chains[$chain_name]

			if ($null -eq $chain) {
				throw "In Workflow '${name}': A Chain named '${chain_name}' does not exist."
			}
		}

		$workflow = [Workflow]@{
			Name = $name
			Chain = $chain
		}

		$workflow.InputOverrides = foreach ($override in $input_overrides) {
			if ([string]::IsNullOrWhiteSpace($override.Name)) {
				throw "In Workflow '${name}': In 'InputOverrides': 'Name' must not be empty."
			}
			elseif (-not $chain.Inputs.ContainsKey($override.Name)) {
				throw (
					"In Workflow '${name}': Cannot override input '$( $override.Name )' " +
					"on chain '${chain_name}': Input does not exist."
				)
			}

			[InputOverride]@{
				ChainInput = $chain.Inputs[$override.Name]
				Value = $override.Value
			}
		}

		$this.Workflows[$name] = $workflow
	}


	[void] AddTextureGroup([string] $name, [string] $workflow_name, [string[]] $texture_names) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			throw "In 'TextureGroups': 'Name' must not be empty."
		}

		if ($this.TextureGroups.ContainsKey($name)) {
			throw "In TextureGroup '${name}': A TextureGroup named '${name}' already exists."
		}

		[Workflow]$workflow = $null

		if ($workflow_name) {
			$workflow = $this.Workflows[$workflow_name]

			if ($null -eq $workflow) {
				throw "In TextureGroup '${name}': A Workflow named '${workflow_name}' does not exist."
			}
		}

		$group = [TextureGroup]@{
			Name = $name
			Workflow = $workflow
			TextureNames = $texture_names
		}

		$this.TextureGroups[$name] = $group

		foreach ($texture_name in $texture_names) {
			$existing_group = $this.TextureGroupMap[$texture_name]
			if ($this.WarnOnGroupReassignment -and $null -ne $existing_group) {
				Write-Warning (
					"In TextureGroup '${name}': Texture '${texture_name}' " +
					"was previously assigned to group '$( $existing_group.Name )'."
				)
			}

			$this.TextureGroupMap[$texture_name] = $group
		}
	}
}


<#
.SYNOPSIS
Reads the options configuring what textures get upscaled and which workflows to use.
#>
function Read-UpscaleOptions {
	[CmdletBinding()]
	[OutputType([UpscaleOptions])]
	param()

	Write-Host 'Reading upscale options ...'
	$upscale_options_path = Join-Path $ProjectDir 'upscale-options.json'
	[UpscaleOptions]::new([File]::ReadAllText($upscale_options_path))
}
