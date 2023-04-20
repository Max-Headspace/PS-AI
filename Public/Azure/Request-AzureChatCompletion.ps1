function Request-AzureChatCompletion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Alias('Request-AzureChatGPT')]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidatePattern('^[^\s]*$')]   # name field may not contain spaces
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Engine,

        [Parameter()]
        [AllowEmptyString()]
        [Alias('system')]
        [string[]]$RolePrompt,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [Alias('top_p')]
        [double]$TopP,

        [Parameter()]
        [Alias('n')]
        [uint16]$NumberOfAnswers,

        [Parameter()]
        [switch]$Stream = $false,

        [Parameter()]
        [ValidateCount(1, 4)]
        [Alias('stop')]
        [string[]]$StopSequence,

        [Parameter()]
        [ValidateRange(0, 4096)]
        [Alias('max_tokens')]
        [int]$MaxTokens,

        [Parameter()]
        [ValidateRange(-2.0, 2.0)]
        [Alias('presence_penalty')]
        [double]$PresencePenalty,

        [Parameter()]
        [ValidateRange(-2.0, 2.0)]
        [Alias('frequency_penalty')]
        [double]$FrequencyPenalty,

        [Parameter()]
        [Alias('logit_bias')]
        [System.Collections.IDictionary]$LogitBias,

        [Parameter()]
        [string]$User,

        [Parameter()]
        [int]$TimeoutSec = 0,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$MaxRetryCount = 0,

        [Parameter()]
        [System.Uri]$ApiBase,

        [Parameter()]
        [string]$ApiVersion,

        [Parameter()]
        [object]$ApiKey,

        [Parameter()]
        [ValidateSet('azure', 'azure_ad')]
        [string]$AuthType = 'azure',

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [object[]]$History
    )

    begin {
        # Initialize API Key
        [securestring]$SecureToken = Initialize-APIKey -ApiKey $ApiKey

        # Initialize API Base
        $ApiBase = Initialize-AzureAPIBase -ApiBase $ApiBase

        # Get API endpoint
        $OpenAIParameter = Get-AzureOpenAIAPIEndpoint -EndpointName 'Chat.Completion' -Engine $Engine -ApiBase $ApiBase -ApiVersion $ApiVersion

        # Temporal model name
        $Model = 'gpt-3.5-turbo'
    }

    process {
        # Warning
        if ($PSBoundParameters.ContainsKey('Name') -and (-not $PSBoundParameters.ContainsKey('Message'))) {
            Write-Warning 'Name parameter is ignored because the Message parameter is not specified.'
        }

        #region Construct parameters for API request
        $PostBody = [System.Collections.Specialized.OrderedDictionary]::new()
        # No need for Azure
        # $PostBody.model = $Model
        if ($PSBoundParameters.ContainsKey('Temperature')) {
            $PostBody.temperature = $Temperature
        }
        if ($PSBoundParameters.ContainsKey('TopP')) {
            $PostBody.top_p = $TopP
        }
        if ($PSBoundParameters.ContainsKey('NumberOfAnswers')) {
            $PostBody.n = $NumberOfAnswers
        }
        if ($PSBoundParameters.ContainsKey('StopSequence')) {
            $PostBody.stop = $StopSequence
        }
        if ($PSBoundParameters.ContainsKey('MaxTokens')) {
            $PostBody.max_tokens = $MaxTokens
        }
        if ($PSBoundParameters.ContainsKey('PresencePenalty')) {
            $PostBody.presence_penalty = $PresencePenalty
        }
        if ($PSBoundParameters.ContainsKey('FrequencyPenalty')) {
            $PostBody.frequency_penalty = $FrequencyPenalty
        }
        if ($PSBoundParameters.ContainsKey('LogitBias')) {
            $PostBody.logit_bias = Convert-LogitBiasDictionary -InputObject $LogitBias -Model $Model
        }
        if ($PSBoundParameters.ContainsKey('User')) {
            $PostBody.user = $User
        }
        if ($Stream) {
            $PostBody.stream = [bool]$Stream
            # When using the Stream option, limit NumberOfAnswers to 1 to optimize output. (this limit may be relaxed in the future)
            $PostBody.n = 1
        }
        #endregion

        #region Construct messages
        $Messages = [System.Collections.Generic.List[object]]::new()
        # Append past conversations
        foreach ($msg in $History) {
            if ($msg.role -and $msg.content) {
                $tm = [ordered]@{
                    role    = [string]$msg.role
                    content = ([string]$msg.content).Trim()
                }
                # name is optional
                if ($msg.name) {
                    $tm.name = [string]$msg.name
                }
                $Messages.Add($tm)
            }
        }
        # Specifies AI role (only if specified)
        foreach ($rp in $RolePrompt) {
            if (-not [string]::IsNullOrWhiteSpace($rp)) {
                $Messages.Add([ordered]@{
                        role    = 'system'
                        content = $rp.Trim()
                    })
            }
        }
        # Add user message (question)
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $um = [ordered]@{
                role    = 'user'
                content = $Message.Trim()
            }
            # name poperty is optional
            if (-not [string]::IsNullOrWhiteSpace($Name)) {
                $um.name = $Name.Trim()
            }
            $Messages.Add($um)
        }

        # Error if messages is empty.
        if ($Messages.Count -eq 0) {
            Write-Error 'No message is specified. You must specify one or more messages.'
        }

        $PostBody.messages = $Messages.ToArray()
        #endregion

        #region Send API Request (Stream)
        if ($Stream) {
            # Stream output
            Invoke-OpenAIAPIRequest `
                -Method $OpenAIParameter.Method `
                -Uri $OpenAIParameter.Uri `
                -ContentType $OpenAIParameter.ContentType `
                -TimeoutSec $TimeoutSec `
                -MaxRetryCount $MaxRetryCount `
                -ApiKey $SecureToken `
                -AuthType $AuthType `
                -Body $PostBody `
                -Stream $Stream |`
                Where-Object {
                -not [string]::IsNullOrEmpty($_)
            } | ForEach-Object {
                try {
                    $_ | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    Write-Error -Exception $_.Exception
                }
            } | Where-Object {
                $null -ne $_.choices -and $_.choices[0].delta.content -is [string]
            } | ForEach-Object {
                # Writes content to both the Information stream(6>) and the Standard output stream(1>).
                $InfoMsg = [System.Management.Automation.HostInformationMessage]::new()
                $InfoMsg.Message = $_.choices[0].delta.content
                $InfoMsg.NoNewLine = $true
                Write-Information $InfoMsg
                Write-Output $InfoMsg.Message
            }
            return
        }
        #endregion

        #region Send API Request (No Stream)
        else {
            $Response = Invoke-OpenAIAPIRequest `
                -Method $OpenAIParameter.Method `
                -Uri $OpenAIParameter.Uri `
                -ContentType $OpenAIParameter.ContentType `
                -TimeoutSec $TimeoutSec `
                -MaxRetryCount $MaxRetryCount `
                -ApiKey $SecureToken `
                -AuthType $AuthType `
                -Body $PostBody

            # error check
            if ($null -eq $Response) {
                return
            }
        }
        #endregion

        #region Parse response object
        try {
            $Response = $Response | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Error -Exception $_.Exception
        }
        if ($null -ne $Response.choices) {
            $ResponseContent = $Response.choices.message
        }
        # For history, add AI response to messages list.
        if (@($ResponseContent).Count -ge 1) {
            $Messages.Add([ordered]@{
                    role    = @($ResponseContent)[0].role
                    content = @($ResponseContent)[0].content
                })
        }
        #endregion

        #region Output
        # Add custom type name and properties to output object.
        $Response.PSObject.TypeNames.Insert(0, 'PSOpenAI.Chat.Completion')
        if ($unixtime = $Response.created -as [long]) {
            # convert unixtime to [DateTime] for read suitable
            $Response | Add-Member -MemberType NoteProperty -Name 'created' -Value ([System.DateTimeOffset]::FromUnixTimeSeconds($unixtime).LocalDateTime) -Force
        }
        $Response | Add-Member -MemberType NoteProperty -Name 'Message' -Value $Message.Trim()
        $Response | Add-Member -MemberType NoteProperty -Name 'Answer' -Value ([string[]]$ResponseContent.content)
        $Response | Add-Member -MemberType NoteProperty -Name 'History' -Value $Messages.ToArray()
        Write-Output $Response
        #endregion
    }

    end {

    }
}
