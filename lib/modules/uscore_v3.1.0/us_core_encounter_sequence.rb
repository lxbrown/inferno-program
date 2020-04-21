# frozen_string_literal: true

require_relative './data_absent_reason_checker'

module Inferno
  module Sequence
    class USCore310EncounterSequence < SequenceBase
      include Inferno::DataAbsentReasonChecker

      title 'Encounter'

      description 'Verify that Encounter resources on the FHIR server follow the US Core Implementation Guide'

      test_id_prefix 'USCE'

      requires :token
      conformance_supports :Encounter
      delayed_sequence

      def validate_resource_item(resource, property, value)
        case property

        when '_id'
          values = value.split(/(?<!\\),/).each { |str| str.gsub!('\,', ',') }
          value_found = resolve_element_from_path(resource, 'id') { |value_in_resource| values.include? value_in_resource }
          assert value_found.present?, '_id on resource does not match _id requested'

        when 'class'
          values = value.split(/(?<!\\),/).each { |str| str.gsub!('\,', ',') }
          value_found = resolve_element_from_path(resource, 'local_class.code') { |value_in_resource| values.include? value_in_resource }
          assert value_found.present?, 'class on resource does not match class requested'

        when 'date'
          value_found = resolve_element_from_path(resource, 'period') { |date| validate_date_search(value, date) }
          assert value_found.present?, 'date on resource does not match date requested'

        when 'identifier'
          values = value.split(/(?<!\\),/).each { |str| str.gsub!('\,', ',') }
          value_found = resolve_element_from_path(resource, 'identifier.value') { |value_in_resource| values.include? value_in_resource }
          assert value_found.present?, 'identifier on resource does not match identifier requested'

        when 'patient'
          value_found = resolve_element_from_path(resource, 'subject.reference') { |reference| [value, 'Patient/' + value].include? reference }
          assert value_found.present?, 'patient on resource does not match patient requested'

        when 'status'
          values = value.split(/(?<!\\),/).each { |str| str.gsub!('\,', ',') }
          value_found = resolve_element_from_path(resource, 'status') { |value_in_resource| values.include? value_in_resource }
          assert value_found.present?, 'status on resource does not match status requested'

        when 'type'
          values = value.split(/(?<!\\),/).each { |str| str.gsub!('\,', ',') }
          value_found = resolve_element_from_path(resource, 'type.coding.code') { |value_in_resource| values.include? value_in_resource }
          assert value_found.present?, 'type on resource does not match type requested'

        end
      end

      def perform_search_with_status(reply, search_param)
        begin
          parsed_reply = JSON.parse(reply.body)
          assert parsed_reply['resourceType'] == 'OperationOutcome', 'Server returned a status of 400 without an OperationOutcome.'
        rescue JSON::ParserError
          assert false, 'Server returned a status of 400 without an OperationOutcome.'
        end

        warning do
          assert @instance.server_capabilities&.search_documented?('Encounter'),
                 %(Server returned a status of 400 with an OperationOutcome, but the
                search interaction for this resource is not documented in the
                CapabilityStatement. If this response was due to the server
                requiring a status parameter, the server must document this
                requirement in its CapabilityStatement.)
        end

        ['planned', 'arrived', 'triaged', 'in-progress', 'onleave', 'finished', 'cancelled', 'entered-in-error', 'unknown'].each do |status_value|
          params_with_status = search_param.merge('status': status_value)
          reply = get_resource_by_params(versioned_resource_class('Encounter'), params_with_status)
          assert_response_ok(reply)
          assert_bundle_response(reply)

          entries = reply.resource.entry.select { |entry| entry.resource.resourceType == 'Encounter' }
          next if entries.blank?

          search_param.merge!('status': status_value)
          break
        end

        reply
      end

      details %(
        The #{title} Sequence tests `#{title.gsub(/\s+/, '')}` resources associated with the provided patient.
      )

      def patient_ids
        @instance.patient_ids.split(',').map(&:strip)
      end

      @resources_found = false

      MUST_SUPPORTS = {
        extensions: [],
        slices: [],
        elements: [
          {
            path: 'identifier'
          },
          {
            path: 'identifier.system'
          },
          {
            path: 'identifier.value'
          },
          {
            path: 'status'
          },
          {
            path: 'local_class'
          },
          {
            path: 'type'
          },
          {
            path: 'subject'
          },
          {
            path: 'participant'
          },
          {
            path: 'participant.type'
          },
          {
            path: 'participant.period'
          },
          {
            path: 'participant.individual'
          },
          {
            path: 'period'
          },
          {
            path: 'reasonCode'
          },
          {
            path: 'hospitalization'
          },
          {
            path: 'hospitalization.dischargeDisposition'
          },
          {
            path: 'location'
          },
          {
            path: 'location.location'
          }
        ]
      }.freeze

      test :resource_read do
        metadata do
          id '01'
          name 'Server returns correct Encounter resource from the Encounter read interaction'
          link 'https://www.hl7.org/fhir/us/core/CapabilityStatement-us-core-server.html'
          description %(
            Reference to Encounter can be resolved and read.
          )
          versions :r4
        end

        skip_if_known_not_supported(:Encounter, [:read])

        encounter_references = @instance.resource_references.select { |reference| reference.resource_type == 'Encounter' }
        skip 'No Encounter references found from the prior searches' if encounter_references.blank?

        @encounter_ary = encounter_references.map do |reference|
          validate_read_reply(
            FHIR::Encounter.new(id: reference.resource_id),
            FHIR::Encounter,
            check_for_data_absent_reasons
          )
        end
        @encounter = @encounter_ary.first
        @resources_found = @encounter.present?
      end

      test :validate_resources do
        metadata do
          id '02'
          name 'Encounter resources returned conform to US Core R4 profiles'
          link 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-encounter'
          description %(

            This test checks if the resources returned from prior searches conform to the US Core profiles.
            This includes checking for missing data elements and valueset verification.

          )
          versions :r4
        end

        skip_if_not_found(resource_type: 'Encounter', delayed: true)
        test_resources_against_profile('Encounter')
        bindings = [
          {
            type: 'code',
            strength: 'required',
            system: 'http://hl7.org/fhir/ValueSet/identifier-use',
            path: 'identifier.use'
          },
          {
            type: 'CodeableConcept',
            strength: 'extensible',
            system: 'http://hl7.org/fhir/ValueSet/identifier-type',
            path: 'identifier.type'
          },
          {
            type: 'code',
            strength: 'required',
            system: 'http://hl7.org/fhir/ValueSet/encounter-status',
            path: 'status'
          },
          {
            type: 'code',
            strength: 'required',
            system: 'http://hl7.org/fhir/ValueSet/encounter-status',
            path: 'statusHistory.status'
          },
          {
            type: 'Coding',
            strength: 'extensible',
            system: 'http://terminology.hl7.org/ValueSet/v3-ActEncounterCode',
            path: 'local_class'
          },
          {
            type: 'Coding',
            strength: 'extensible',
            system: 'http://terminology.hl7.org/ValueSet/v3-ActEncounterCode',
            path: 'classHistory.local_class'
          },
          {
            type: 'CodeableConcept',
            strength: 'extensible',
            system: 'http://hl7.org/fhir/us/core/ValueSet/us-core-encounter-type',
            path: 'type'
          },
          {
            type: 'CodeableConcept',
            strength: 'extensible',
            system: 'http://hl7.org/fhir/ValueSet/encounter-participant-type',
            path: 'participant.type'
          },
          {
            type: 'code',
            strength: 'required',
            system: 'http://hl7.org/fhir/ValueSet/encounter-location-status',
            path: 'location.status'
          }
        ]
        invalid_binding_messages = []
        invalid_binding_resources = Set.new
        bindings.select { |binding_def| binding_def[:strength] == 'required' }.each do |binding_def|
          begin
            invalid_bindings = resources_with_invalid_binding(binding_def, @encounter_ary)
          rescue Inferno::Terminology::UnknownValueSetException => e
            warning do
              assert false, e.message
            end
            invalid_bindings = []
          end
          invalid_bindings.each { |invalid| invalid_binding_resources << "#{invalid[:resource]&.resourceType}/#{invalid[:resource].id}" }
          invalid_binding_messages.concat(invalid_bindings.map { |invalid| invalid_binding_message(invalid, binding_def) })
        end
        assert invalid_binding_messages.blank?, "#{invalid_binding_messages.count} invalid required binding(s) found in #{invalid_binding_resources.count} resources:" \
                                                "#{invalid_binding_messages.join('. ')}"

        bindings.select { |binding_def| binding_def[:strength] == 'extensible' }.each do |binding_def|
          begin
            invalid_bindings = resources_with_invalid_binding(binding_def, @encounter_ary)
            binding_def_new = binding_def
            # If the valueset binding wasn't valid, check if the codes are in the stated codesystem
            if invalid_bindings.present?
              invalid_bindings = resources_with_invalid_binding(binding_def.except(:system), @encounter_ary)
              binding_def_new = binding_def.except(:system)
            end
          rescue Inferno::Terminology::UnknownValueSetException, Inferno::Terminology::ValueSet::UnknownCodeSystemException => e
            warning do
              assert false, e.message
            end
            invalid_bindings = []
          end
          invalid_binding_messages.concat(invalid_bindings.map { |invalid| invalid_binding_message(invalid, binding_def_new) })
        end
        warning do
          invalid_binding_messages.each do |error_message|
            assert false, error_message
          end
        end
      end

      test 'All must support elements are provided in the Encounter resources returned.' do
        metadata do
          id '03'
          link 'http://www.hl7.org/fhir/us/core/general-guidance.html#must-support'
          description %(

            US Core Responders SHALL be capable of populating all data elements as part of the query results as specified by the US Core Server Capability Statement.
            This will look through all Encounter resources returned from prior searches to see if any of them provide the following must support elements:

            identifier

            identifier.system

            identifier.value

            status

            class

            type

            subject

            participant

            participant.type

            participant.period

            participant.individual

            period

            reasonCode

            hospitalization

            hospitalization.dischargeDisposition

            location

            location.location

          )
          versions :r4
        end

        skip_if_not_found(resource_type: 'Encounter', delayed: true)

        missing_must_support_elements = MUST_SUPPORTS[:elements].reject do |element|
          @encounter_ary&.any? do |resource|
            value_found = resolve_element_from_path(resource, element[:path]) { |value| element[:fixed_value].blank? || value == element[:fixed_value] }
            value_found.present?
          end
        end
        missing_must_support_elements.map! { |must_support| "#{must_support[:path]}#{': ' + must_support[:fixed_value] if must_support[:fixed_value].present?}" }

        skip_if missing_must_support_elements.present?,
                "Could not find #{missing_must_support_elements.join(', ')} in the #{@encounter_ary&.length} provided Encounter resource(s)"
        @instance.save!
      end

      test 'Every reference within Encounter resource is valid and can be read.' do
        metadata do
          id '04'
          link 'http://hl7.org/fhir/references.html'
          description %(
            This test checks if references found in resources from prior searches can be resolved.
          )
          versions :r4
        end

        skip_if_known_not_supported(:Encounter, [:search, :read])
        skip_if_not_found(resource_type: 'Encounter', delayed: true)

        validated_resources = Set.new
        max_resolutions = 50

        @encounter_ary&.each do |resource|
          validate_reference_resolutions(resource, validated_resources, max_resolutions) if validated_resources.length < max_resolutions
        end
      end
    end
  end
end
