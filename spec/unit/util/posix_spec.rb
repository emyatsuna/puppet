require 'spec_helper'

require 'puppet/util/posix'

class PosixTest
  include Puppet::Util::POSIX
end

describe Puppet::Util::POSIX do
  before do
    @posix = PosixTest.new
  end

  describe '.groups_of' do
    let(:mock_groups) do
      [
        ['group1', ['user1', 'user2']],
        ['group2', ['user2']],
        ['group1', ['user1', 'user2']],
        ['group3', ['user1']],
        ['group4', ['user2']]
      ].map do |(name, members)|
        group_struct = double("Group #{name}")
        allow(group_struct).to receive(:name).and_return(name)
        allow(group_struct).to receive(:mem).and_return(members)

        group_struct
      end
    end

    before(:each) do
      etc_stub = receive(:group)
      mock_groups.each do |mock_group|
        etc_stub = etc_stub.and_yield(mock_group)
      end
      allow(Puppet::Etc).to etc_stub
    end

    it 'returns the groups of the given user' do
      expect(Puppet::Util::POSIX.groups_of('user1')).to eql(
        ['group1', 'group3']
      )
    end
  end

  [:group, :gr].each do |name|
    it "should return :gid as the field for #{name}" do
      expect(@posix.idfield(name)).to eq(:gid)
    end

    it "should return :getgrgid as the id method for #{name}" do
      expect(@posix.methodbyid(name)).to eq(:getgrgid)
    end

    it "should return :getgrnam as the name method for #{name}" do
      expect(@posix.methodbyname(name)).to eq(:getgrnam)
    end
  end

  [:user, :pw, :passwd].each do |name|
    it "should return :uid as the field for #{name}" do
      expect(@posix.idfield(name)).to eq(:uid)
    end

    it "should return :getpwuid as the id method for #{name}" do
      expect(@posix.methodbyid(name)).to eq(:getpwuid)
    end

    it "should return :getpwnam as the name method for #{name}" do
      expect(@posix.methodbyname(name)).to eq(:getpwnam)
    end
  end

  describe "when retrieving a posix field" do
    before do
      @thing = double('thing', :field => "asdf")
    end

    it "should fail if no id was passed" do
      expect { @posix.get_posix_field("asdf", "bar", nil) }.to raise_error(Puppet::DevError)
    end

    describe "and the id is an integer" do
      it "should log an error and return nil if the specified id is greater than the maximum allowed ID" do
        Puppet[:maximum_uid] = 100
        expect(Puppet).to receive(:err)

        expect(@posix.get_posix_field("asdf", "bar", 200)).to be_nil
      end

      it "should use the method return by :methodbyid and return the specified field" do
        expect(Etc).to receive(:getgrgid).and_return(@thing)

        expect(@thing).to receive(:field).and_return("myval")

        expect(@posix.get_posix_field(:gr, :field, 200)).to eq("myval")
      end

      it "should return nil if the method throws an exception" do
        expect(Etc).to receive(:getgrgid).and_raise(ArgumentError)

        expect(@thing).not_to receive(:field)

        expect(@posix.get_posix_field(:gr, :field, 200)).to be_nil
      end
    end

    describe "and the id is not an integer" do
      it "should use the method return by :methodbyid and return the specified field" do
        expect(Etc).to receive(:getgrnam).and_return(@thing)

        expect(@thing).to receive(:field).and_return("myval")

        expect(@posix.get_posix_field(:gr, :field, "asdf")).to eq("myval")
      end

      it "should return nil if the method throws an exception" do
        expect(Etc).to receive(:getgrnam).and_raise(ArgumentError)

        expect(@thing).not_to receive(:field)

        expect(@posix.get_posix_field(:gr, :field, "asdf")).to be_nil
      end
    end
  end

  describe "when returning the gid" do
    before do
      allow(@posix).to receive(:get_posix_field)
    end

    describe "and the group is an integer" do
      it "should convert integers specified as a string into an integer" do
        expect(@posix).to receive(:get_posix_field).with(:group, :name, 100)

        @posix.gid("100")
      end

      it "should look up the name for the group" do
        expect(@posix).to receive(:get_posix_field).with(:group, :name, 100)

        @posix.gid(100)
      end

      it "should return nil if the group cannot be found" do
        expect(@posix).to receive(:get_posix_field).once.and_return(nil)
        expect(@posix).not_to receive(:search_posix_field)

        expect(@posix.gid(100)).to be_nil
      end

      it "should use the found name to look up the id" do
        expect(@posix).to receive(:get_posix_field).with(:group, :name, 100).and_return("asdf")
        expect(@posix).to receive(:get_posix_field).with(:group, :gid, "asdf").and_return(100)

        expect(@posix.gid(100)).to eq(100)
      end

      # LAK: This is because some platforms have a broken Etc module that always return
      # the same group.
      it "should use :search_posix_field if the discovered id does not match the passed-in id" do
        expect(@posix).to receive(:get_posix_field).with(:group, :name, 100).and_return("asdf")
        expect(@posix).to receive(:get_posix_field).with(:group, :gid, "asdf").and_return(50)

        expect(@posix).to receive(:search_posix_field).with(:group, :gid, 100).and_return("asdf")

        expect(@posix.gid(100)).to eq("asdf")
      end
    end

    describe "and the group is a string" do
      it "should look up the gid for the group" do
        expect(@posix).to receive(:get_posix_field).with(:group, :gid, "asdf")

        @posix.gid("asdf")
      end

      it "should return nil if the group cannot be found" do
        expect(@posix).to receive(:get_posix_field).once.and_return(nil)
        expect(@posix).not_to receive(:search_posix_field)

        expect(@posix.gid("asdf")).to be_nil
      end

      it "should use the found gid to look up the nam" do
        expect(@posix).to receive(:get_posix_field).with(:group, :gid, "asdf").and_return(100)
        expect(@posix).to receive(:get_posix_field).with(:group, :name, 100).and_return("asdf")

        expect(@posix.gid("asdf")).to eq(100)
      end

      it "should use :search_posix_field if the discovered name does not match the passed-in name" do
        expect(@posix).to receive(:get_posix_field).with(:group, :gid, "asdf").and_return(100)
        expect(@posix).to receive(:get_posix_field).with(:group, :name, 100).and_return("boo")

        expect(@posix).to receive(:search_posix_field).with(:group, :gid, "asdf").and_return("asdf")

        expect(@posix.gid("asdf")).to eq("asdf")
      end
    end
  end

  describe "when returning the uid" do
    before do
      allow(@posix).to receive(:get_posix_field)
    end

    describe "and the group is an integer" do
      it "should convert integers specified as a string into an integer" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :name, 100)

        @posix.uid("100")
      end

      it "should look up the name for the group" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :name, 100)

        @posix.uid(100)
      end

      it "should return nil if the group cannot be found" do
        expect(@posix).to receive(:get_posix_field).once.and_return(nil)
        expect(@posix).not_to receive(:search_posix_field)

        expect(@posix.uid(100)).to be_nil
      end

      it "should use the found name to look up the id" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :name, 100).and_return("asdf")
        expect(@posix).to receive(:get_posix_field).with(:passwd, :uid, "asdf").and_return(100)

        expect(@posix.uid(100)).to eq(100)
      end

      # LAK: This is because some platforms have a broken Etc module that always return
      # the same group.
      it "should use :search_posix_field if the discovered id does not match the passed-in id" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :name, 100).and_return("asdf")
        expect(@posix).to receive(:get_posix_field).with(:passwd, :uid, "asdf").and_return(50)

        expect(@posix).to receive(:search_posix_field).with(:passwd, :uid, 100).and_return("asdf")

        expect(@posix.uid(100)).to eq("asdf")
      end
    end

    describe "and the group is a string" do
      it "should look up the uid for the group" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :uid, "asdf")

        @posix.uid("asdf")
      end

      it "should return nil if the group cannot be found" do
        expect(@posix).to receive(:get_posix_field).once.and_return(nil)
        expect(@posix).not_to receive(:search_posix_field)

        expect(@posix.uid("asdf")).to be_nil
      end

      it "should use the found uid to look up the nam" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :uid, "asdf").and_return(100)
        expect(@posix).to receive(:get_posix_field).with(:passwd, :name, 100).and_return("asdf")

        expect(@posix.uid("asdf")).to eq(100)
      end

      it "should use :search_posix_field if the discovered name does not match the passed-in name" do
        expect(@posix).to receive(:get_posix_field).with(:passwd, :uid, "asdf").and_return(100)
        expect(@posix).to receive(:get_posix_field).with(:passwd, :name, 100).and_return("boo")

        expect(@posix).to receive(:search_posix_field).with(:passwd, :uid, "asdf").and_return("asdf")

        expect(@posix.uid("asdf")).to eq("asdf")
      end
    end
  end

  it "should be able to iteratively search for posix values" do
    expect(@posix).to respond_to(:search_posix_field)
  end
end
